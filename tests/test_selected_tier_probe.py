import copy
import unittest
import importlib.util
from pathlib import Path
_spec = importlib.util.spec_from_file_location("selected_probe", Path(__file__).parents[1] / "tools/probe_native_graphics.py")
_PROBE = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_PROBE)
selected_intel_compatibility = _PROBE.selected_intel_compatibility

class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.backend = {'display':'macOS','renderer':'gl_compatibility','driver':'opengl3',
                        'adapter':'Apple Software Renderer','api':'4.1','user_data_dir':'/tmp/fixture'}
        self.profile = {'requested_renderer':'gl_compatibility','requested_driver':'opengl3',
                        'status':'passed','returncode':0,'actual_backend':self.backend,
                        'screenshots':[{'file':p,'width':1280,'height':720,'sha256':'a'*64} for p in _PROBE.PNG_NAMES]}
        self.runtime = {'display':'macOS','renderer':'gl_compatibility','driver':'opengl3','checks':200,
                        'walk_metres':11,'drive_metres':21,'engine':{'major':4,'minor':7,'patch':2},
                        'conditions':[{'conditions':c} for c in ('day','dusk','rain')]}
    def accept(self, target='macos', arch='x86_64', enabled=True):
        return selected_intel_compatibility(target,arch,enabled,self.profile,self.runtime)
    def test_positive_explicit_full_compatibility(self): self.assertTrue(self.accept())
    def test_target_scope(self):
        for target,arch,enabled in [('windows','x86_64',True),('macos','arm64',True),('macos','unknown',True),('macos','x86_64',False),('macos','x86_64',1)]:
            with self.subTest((target,arch,enabled)): self.assertFalse(self.accept(target,arch,enabled))
    def test_selected_failure_is_fatal(self):
        for status in ('timed_out','failed_after_backend_initialization','invalid_evidence','requested_backend_not_used','clean_angle_fallback_detected'):
            self.profile['status']=status
            with self.subTest(status): self.assertFalse(self.accept())
    def test_nonzero_return(self):
        for code in (-4,-6,124):
            self.profile['returncode']=code
            with self.subTest(code): self.assertFalse(self.accept())
    def test_headless_or_wrong_driver(self):
        for field,value in [('display','headless'),('driver','vulkan'),('driver','opengl3_angle'),('renderer','mobile'),('adapter','')]:
            self.profile['actual_backend']=copy.deepcopy(self.backend)
            self.profile['actual_backend'][field]=value
            with self.subTest((field,value)): self.assertFalse(self.accept())
    def test_insufficient_or_forged_checks(self):
        for checks in (199,1,200.0,True):
            self.runtime['checks']=checks
            with self.subTest(checks): self.assertFalse(self.accept())
    def test_missing_or_wrong_images(self):
        self.profile['screenshots'].pop(); self.assertFalse(self.accept())
        self.setUp(); self.profile['screenshots'][3]['file']='stale.png'; self.assertFalse(self.accept())
        self.setUp(); self.profile['screenshots'][3]['sha256']='bad'; self.assertFalse(self.accept())
    def test_no_actual_gameplay(self):
        for field,value in [('walk_metres',0),('drive_metres',0),('drive_metres',float('nan')),('conditions',[])]:
            self.setUp(); self.runtime[field]=value
            with self.subTest((field,value)): self.assertFalse(self.accept())
    def test_report_driver_mismatch(self):
        self.runtime['driver']='opengl3_angle'; self.assertFalse(self.accept())
    def test_classifier_retains_late_errors(self):
        output='SCENE112_VISUAL_OK checks=200\nERROR: actual selected shader or runtime failure\n'
        self.profile['status']=_PROBE.classify(output,0,self.backend,'gl_compatibility','opengl3')
        self.assertEqual(self.profile['status'],'failed_after_backend_initialization')
        self.assertFalse(self.accept())
    def test_research_failures_are_unmodified(self):
        research=[{'status':'failed_before_backend_report','returncode':-6},
                  {'status':'failed_after_backend_initialization','returncode':-4}]
        before=copy.deepcopy(research)
        self.assertTrue(self.accept()); self.assertEqual(research,before)

if __name__ == '__main__': unittest.main()
