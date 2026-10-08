"""Observed native artifact metadata fixtures; not simulated native platform proof."""

import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "platform_probe", Path(__file__).parents[1] / "tools/probe_native_graphics.py"
)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class PlatformProvenance(unittest.TestCase):
    def test_pinned_architectures_use_available_driver(self):
        self.assertEqual(
            probe.profile_drivers("macos", "x86_64"), ("vulkan", "opengl3_angle")
        )
        self.assertEqual(probe.profile_drivers("macos", "arm64"), ("metal", "opengl3"))
        self.assertEqual(
            probe.profile_drivers("windows", "AMD64"), ("d3d12", "opengl3")
        )

    def test_unknown_mac_arch_cannot_guess_driver(self):
        with self.assertRaises(ValueError):
            probe.profile_drivers("macos", "unknown")

    def test_observed_mac_angle_report_is_not_native_opengl(self):
        info = probe.implementation_details(
            {
                "renderer": "gl_compatibility",
                "driver": "opengl3",
                "adapter": "ANGLE Metal Renderer: Apple Paravirtual device",
                "api": "OpenGL ES 3.0 (ANGLE 2.1.1)",
                "vendor": "Google Inc. (Apple)",
            }
        )
        self.assertTrue(info["angle_translation_detected"])
        self.assertTrue(info["virtual_adapter_detected"])
        self.assertEqual(info["angle_backend"], "metal")
        self.assertFalse(info["native_opengl_implementation"])
        self.assertFalse(info["physical_target_gpu_acceptance"])

    def test_actual_native_opengl_signature_remains_distinct(self):
        info = probe.implementation_details(
            {
                "renderer": "gl_compatibility",
                "driver": "opengl3",
                "adapter": "AMD (fixture)",
                "api": "OpenGL 4.1",
                "vendor": "AMD",
            }
        )
        self.assertTrue(info["native_opengl_implementation"])
        self.assertFalse(info["angle_translation_detected"])
        self.assertFalse(info["physical_target_gpu_acceptance"])

    def test_observed_windows_basic_driver_is_software_even_type_one(self):
        info = probe.implementation_details(
            {
                "renderer": "forward_plus",
                "driver": "d3d12",
                "adapter_type": 1,
                "adapter": "Microsoft Basic Render Driver",
                "api": "12_0",
                "vendor": "Microsoft",
            }
        )
        self.assertTrue(info["software_adapter_detected"])
        self.assertFalse(info["physical_target_gpu_acceptance"])

    def test_windows_angle_records_underlying_d3d11_without_truthful_gpu_claim(self):
        info = probe.implementation_details(
            {
                "renderer": "gl_compatibility",
                "driver": "opengl3_angle",
                "adapter": "ANGLE Microsoft Basic Render Driver Direct3D11 vs_5_0 ps_5_0",
                "api": "OpenGL ES 3.0",
                "adapter_type": 0,
            }
        )
        self.assertEqual(info["angle_backend"], "d3d11")
        self.assertTrue(info["software_adapter_detected"])
        self.assertFalse(info["native_opengl_implementation"])


if __name__ == "__main__":
    unittest.main()
