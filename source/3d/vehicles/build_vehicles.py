"""Authored European emergency vehicles for SCENE112, Blender -> embedded GLB.

Original profile geometry, curved wheel openings, framed glazing, interiors,
lamps, livery, ladder/pump/shutters. Not a conversion of the gameplay graybox.
"""
from pathlib import Path
import math
import sys
import bpy
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
import assetkit as k

BASE = Path(__file__).resolve().parents[3]
TEX = BASE / 'assets/textures/vehicles'
OUT = BASE / 'assets/models/vehicles'


def mats():
    return {
        'white': k.material('vehicle_pearl', (0.72, 0.77, 0.77), 0.27, 0.12, TEX),
        'blue': k.material('vehicle_navy', (0.012, 0.060, 0.13), 0.30, 0.12, TEX),
        'red': k.material('appliance_vermilion', (0.48, 0.035, 0.022), 0.30, 0.12, TEX),
        'yellow': k.material('reflective_amber', (0.81, 0.64, 0.085), 0.32),
        'metal': k.material('brushed_alloy', (0.43, 0.49, 0.51), 0.33, 0.88, TEX),
        'rubber': k.material('tyre_rubber', (0.018, 0.021, 0.025), 0.82, 0.0, TEX, 'rubber'),
        'trim': k.material('window_trim', (0.016, 0.025, 0.030), 0.56, 0.0),
        'glass': k.material('automotive_glass', (0.09, 0.18, 0.23), 0.10, 0.2, alpha=0.32),
        'lamp': k.material('lamp_polycarbonate', (0.84, 0.90, 0.91), 0.20, 0.18),
        'tail': k.material('rear_lens', (0.55, 0.035, 0.018), 0.23),
        'beacon': k.material('blue_beacon_lens', (0.015, 0.21, 0.48), 0.17, 0.15),
        'seat': k.material('vehicle_seat_fabric', (0.033, 0.045, 0.052), 0.88, 0.0, TEX, 'fabric')}


def loft(name, sections, mat, root):
    vertices = []
    for y, width, low, top in sections:
        profile = [(-width * 0.87, low), (width * 0.87, low), (width, low + 0.12),
                   (width, top - 0.12), (width * 0.89, top), (-width * 0.89, top),
                   (-width, top - 0.12), (-width, low + 0.12)]
        vertices += [(x, y, z) for x, z in profile]
    faces = [tuple(range(7, -1, -1))]
    for i in range(len(sections) - 1):
        for j in range(8): faces.append((i * 8 + j, i * 8 + (j + 1) % 8, (i + 1) * 8 + (j + 1) % 8, (i + 1) * 8 + j))
    faces.append(tuple((len(sections) - 1) * 8 + j for j in range(8)))
    return k.mesh(name, vertices, faces, mat, root, 0.035)


def window(name, corners, mat, root):
    return k.mesh(name, corners, [(0, 1, 2, 3)], mat, root)


def framed_window(name, corners, material, trim, root, radius=0.024):
    window(name, corners, material, root)
    k.tube(name + '_seal', corners + [corners[0]], radius, trim, root)


def wheel(root, x, y, z, radius, m, name):
    assembly = k.empty(name, (x, y, z))
    k.parent(assembly, root)
    outer = 0.15 if radius < 0.45 else 0.21
    # Lathed tyre cross-section: rounded shoulders and actual inner rim opening.
    profile = [(-1.0, .64), (-1.0, .77), (-.97, .89), (-.85, .975), (-.63, 1.0),
               (.63, 1.0), (.85, .975), (.97, .89), (1.0, .77), (1.0, .64)]
    vertices = [(x + axial * outer, y + math.sin(i * math.tau / 64) * radial * radius,
                 z + math.cos(i * math.tau / 64) * radial * radius)
                for axial, radial in profile for i in range(64)]
    faces = [(j * 64 + i, j * 64 + (i + 1) % 64, ((j + 1) % len(profile)) * 64 + (i + 1) % 64,
              ((j + 1) % len(profile)) * 64 + i) for j in range(len(profile)) for i in range(64)]
    k.mesh(name + '_tyre', vertices, faces, m['rubber'], assembly)
    side = 1 if x > 0 else -1
    face_x = x + side * (outer + 0.008)
    k.cylinder(name + '_rim', (face_x, y, z), radius * 0.66, 0.035, m['metal'], assembly, (1, 0, 0))
    k.cylinder(name + '_hub', (face_x + side * 0.035, y, z), radius * 0.2, 0.08, m['metal'], assembly, (1, 0, 0))
    k.cylinder(name + '_brake', (face_x - side * 0.055, y, z), radius * 0.54, 0.025, m['trim'], assembly, (1, 0, 0))
    for i in range(10):
        angle = i * math.tau / 10
        spoke = k.box(name + '_spoke', (face_x + side * 0.025, y + math.sin(angle) * radius * 0.35, z + math.cos(angle) * radius * 0.35),
                      (0.035, 0.032, radius * 0.46), m['metal'], assembly, 0.009)
        spoke.rotation_euler.x = -angle
    for i in range(36):
        angle = i * math.tau / 36
        tread = k.box(name + '_tread', (x, y + math.sin(angle) * radius * 0.998, z + math.cos(angle) * radius * 0.998),
                      (outer * 1.15, radius * 0.025, 0.006), m['rubber'], assembly, 0.001)
        tread.rotation_euler.x = -angle
    # Join wheel pieces into one mesh, retaining its parent as a runtime spin node.
    join_children(assembly, name + '_mesh')


def join_children(root, name):
    meshes = [o for o in root.children if o.type == 'MESH']
    if not meshes: return
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes: obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    bpy.context.object.name = name


def arches(body, root, positions, radius):
    for y, z in positions:
        bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=radius, depth=3.2, location=(0, y, z), rotation=(0, math.pi / 2, 0))
        cutter = bpy.context.object
        modifier = body.modifiers.new('Sculpted wheel opening', 'BOOLEAN')
        modifier.operation = 'DIFFERENCE'
        modifier.solver = 'EXACT'
        modifier.object = cutter
        k.apply(body, modifier)
        bpy.data.objects.remove(cutter, do_unlink=True)
    k.bevel(body, 0.012, 2)
    k.uv(body)


def police_car():
    k.clean()
    root = k.empty('PoliceCar')
    m = mats()
    sections = [(-2.18, 0.72, 0.34, 0.85), (-1.93, 0.88, 0.33, 1.01), (-1.40, 0.94, 0.32, 1.04),
                (-0.55, 0.97, 0.32, 1.04), (0.65, 0.96, 0.32, 1.04), (1.38, 0.91, 0.33, 0.99), (1.98, 0.83, 0.35, 0.96), (2.23, 0.74, 0.40, 0.89)]
    body = loft('SculptedBodyShell', sections, m['white'], root)
    arches(body, root, [(-1.38, 0.39), (1.38, 0.39)], 0.435)
    k.box('Underbody', (0, 0, 0.34), (1.55, 3.9, 0.13), m['trim'], root)
    k.box('RoundedRoof', (0, -0.10, 1.49), (1.42, 1.36, 0.13), m['white'], root, 0.060)
    front = [(-0.79, 0.94, 1.06), (0.79, 0.94, 1.06), (0.69, 0.52, 1.47), (-0.69, 0.52, 1.47)]
    rear = [(-0.70, -0.79, 1.45), (0.70, -0.79, 1.45), (0.83, -1.28, 1.05), (-0.83, -1.28, 1.05)]
    framed_window('Windscreen', front, m['glass'], m['trim'], root)
    framed_window('RearGlass', rear, m['glass'], m['trim'], root)
    for side in [-1, 1]:
        x = side * 0.925
        front_side = [(x, 0.86, 1.06), (x, -0.08, 1.06), (side * 0.71, -0.08, 1.46), (side * 0.72, 0.51, 1.46)]
        rear_side = [(x, -0.17, 1.06), (x, -1.19, 1.06), (side * 0.72, -0.73, 1.46), (side * 0.71, -0.17, 1.46)]
        framed_window('FrontDoorGlass', front_side, m['glass'], m['trim'], root)
        framed_window('RearDoorGlass', rear_side, m['glass'], m['trim'], root)
        k.tube('DoorPanelSeam', [(x, 0.86, 1.0), (side * 0.98, 0.74, 0.47), (side * 0.98, -0.13, 0.47), (x, -0.13, 1.06)], 0.006, m['trim'], root)
        k.tube('RearPanelSeam', [(x, -0.16, 1.06), (side * 0.98, -0.17, 0.48), (side * 0.94, -1.16, 0.50), (side * 0.93, -1.24, 1.02)], 0.006, m['trim'], root)
        for y in [0.1, -0.7]: k.box('RecessedDoorHandle', (side * 0.967, y, 0.97), (0.025, 0.15, 0.025), m['metal'], root, 0.01)
        mirror = k.sphere('AerodynamicMirror', (side * 1.08, 0.58, 1.18), (0.15, 0.11, 0.07), m['white'], root)
        k.box('MirrorGlass', (side * 1.09, 0.47, 1.18), (0.21, 0.014, 0.10), m['metal'], root, 0.01)
        k.tube('MirrorMount', [(x, 0.6, 1.05), (side * 1.06, 0.60, 1.18)], 0.032, m['trim'], root)
        # Original navy panels and amber feature stripe, not an official livery.
        k.box('FictionalNavyPanel', (side * 0.976, 0.03, 0.78), (0.01, 1.58, 0.20), m['blue'], root, 0.005)
        k.box('AmberAccent', (side * 0.985, 0.15, 0.90), (0.012, 1.2, 0.028), m['yellow'], root, 0.003)
        for y in [-1.38, 1.38]:
            wheel(root, side * 0.94, y, 0.39, 0.39, m, ('Wheel_R' if side > 0 else 'Wheel_L') + ('F' if y > 0 else 'R'))
            points = [(side * 0.968, y + math.cos(a) * 0.44, 0.39 + math.sin(a) * 0.44) for a in np_angles(20)]
            k.tube('RolledFenderEdge', points, 0.018, m['white'], root)
    k.box('RoundedLowerBumper', (0, 2.14, 0.46), (1.48, 0.25, 0.20), m['white'], root, 0.07)
    k.box('FrontGrille', (0, 2.245, 0.70), (0.77, 0.055, 0.23), m['trim'], root, 0.04)
    for z in [0.65, 0.72, 0.79]: k.box('GrilleSlat', (0, 2.28, z), (0.68, 0.015, 0.013), m['metal'], root, 0.004)
    k.box('FrontPlateRecess', (0, 2.26, 0.495), (0.54, 0.012, 0.14), m['trim'], root, 0.009)
    k.box('FrontPlate', (0, 2.27, 0.50), (0.50, 0.008, 0.12), m['yellow'], root, 0.006)
    k.label('FictionalPlate', 'NK-112-X', (0, 2.276, 0.472), 0.068, m['trim'], root, (math.pi / 2, 0, math.pi))
    for x in [-0.52, 0.52]:
        k.box('HeadlampHousing', (x, 2.221, 0.825), (0.36, 0.055, 0.105), m['trim'], root, 0.027)
        k.box('HeadlampLens', (x, 2.253, 0.827), (0.315, 0.012, 0.07), m['lamp'], root, 0.023)
        for offset in [-0.075, 0.075]:
            k.cylinder('HeadlampProjector', (x + offset, 2.263, 0.827), 0.024, 0.008, m['metal'], root, (0, 1, 0), 24)
        k.tube('LEDRunningLamp', [(x - .13, 2.269, .843), (x + .13, 2.269, .843), (x + .13, 2.269, .812)], .005, m['lamp'], root)
        k.box('RearLamp', (x, -2.04, 0.91), (0.36, 0.10, 0.12), m['tail'], root, 0.03)
    for x in [-0.37, 0.37]:
        seat = k.box('SeatCushion', (x, -0.12, 0.72), (0.52, 0.56, 0.13), m['seat'], root, 0.065)
        back = k.box('SeatBack', (x, -0.41, 1.02), (0.52, 0.14, 0.61), m['seat'], root, 0.07)
        back.rotation_euler.x = math.radians(-8)
        k.sphere('SeatHeadrest', (x, -0.44, 1.31), (0.19, 0.06, 0.11), m['seat'], root)
    k.box('Dashboard', (0, 0.75, 0.99), (1.38, 0.28, 0.18), m['trim'], root, 0.055)
    k.tube('SteeringWheel', [(-0.37 + math.cos(a) * 0.14, 0.55, 1.05 + math.sin(a) * 0.14) for a in [i * math.tau / 32 for i in range(33)]], 0.014, m['trim'], root)
    k.box('LightbarMount', (0, -0.07, 1.58), (1.04, 0.23, 0.07), m['trim'], root, 0.03)
    for x in [-0.36, 0.36]: k.box('BeaconLens', (x, -0.07, 1.66), (0.32, 0.25, 0.11), m['beacon'], root, 0.045)
    # A surface applique follows the hood profile rather than hovering above it.
    window('BonnetNavyApplique', [(-.35, 1.14, 1.008), (.35, 1.14, 1.008), (.35, 1.82, .970), (-.35, 1.82, .970)], m['blue'], root)
    k.label('BonnetType', 'SCENE 112', (0, 1.61, .9850), 0.106, m['white'], root, (0.050, 0, math.pi))
    join_children(root, 'PoliceBodyDetails')
    k.finish(root, OUT, 'police_car', 6, 1.8)


def np_angles(count):
    return [i * math.pi / (count - 1) for i in range(count)]


def fire_truck():
    k.clean()
    root = k.empty('FireTruck')
    m = mats()
    k.box('HeavyChassis', (0, -0.10, 0.70), (2.12, 6.0, 0.35), m['trim'], root, 0.06)
    body = loft('ApplianceCompartmentBody', [(-3.03, 1.06, 0.72, 2.70), (-2.78, 1.17, 0.72, 2.80), (0.58, 1.17, 0.72, 2.80), (0.85, 1.10, 0.74, 2.73)], m['red'], root)
    arches(body, root, [(-1.63, 0.55)], 0.59)
    cab = loft('RoundedCrewCab', [(0.80, 1.13, 0.70, 1.30), (1.60, 1.14, 0.70, 1.38), (2.80, 1.02, 0.74, 1.36), (3.05, 0.88, 0.78, 1.19)], m['red'], root)
    arches(cab, root, [(1.87, 0.55)], 0.59)
    k.box('CrewCabRoof', (0, 1.58, 2.83), (2.04, 2.20, 0.16), m['red'], root, 0.12)
    front = [(-0.99, 2.73, 1.42), (0.99, 2.73, 1.42), (0.89, 2.45, 2.76), (-0.89, 2.45, 2.76)]
    framed_window('TruckWindscreen', front, m['glass'], m['trim'], root, 0.037)
    k.tube('WindscreenDivider', [(0, 2.73, 1.42), (0, 2.45, 2.76)], 0.026, m['trim'], root)
    # Visible crew cabin with seats, headrests, instrument binnacle and wheel.
    for x in [-0.49, 0.49]:
        for y in [1.16, 2.10]:
            k.box('CrewSeatCushion', (x, y, 1.27), (.54, .55, .16), m['seat'], root, .065)
            back = k.box('CrewSeatBack', (x, y - .24, 1.75), (.52, .16, .80), m['seat'], root, .075)
            back.rotation_euler.x = -.10
            k.sphere('CrewSeatHeadrest', (x, y - .27, 2.16), (.20, .07, .115), m['seat'], root)
    k.box('TruckDashboard', (0, 2.49, 1.46), (1.82, .30, .22), m['trim'], root, .06)
    k.box('InstrumentBinnacle', (-.49, 2.37, 1.62), (.46, .23, .15), m['trim'], root, .04)
    k.tube('TruckSteeringWheel', [(-.49 + math.cos(a) * .18, 2.20, 1.65 + math.sin(a) * .18) for a in [i * math.tau / 32 for i in range(33)]], .019, m['trim'], root)
    for side in [-1, 1]:
        x = side * 1.11
        k.tube('CabRearPillar', [(x, 0.74, 1.25), (side * 0.99, 0.61, 2.81)], 0.10, m['red'], root)
        corners = [(x, 2.56, 1.41), (x, 0.77, 1.41), (side * 0.99, 0.70, 2.74), (side * 0.99, 2.39, 2.74)]
        framed_window('CabSideGlass', corners, m['glass'], m['trim'], root, 0.03)
        k.tube('CrewWindowPillar', [(x, 1.50, 1.41), (side * 0.99, 1.5, 2.75)], 0.06, m['red'], root)
        k.box('CrewDoorHandle', (side * 1.18, 1.07, 1.22), (0.04, 0.24, 0.07), m['trim'], root)
        k.box('CabSafetyStripe', (side * 1.17, 1.38, 1.25), (0.016, 1.78, 0.09), m['yellow'], root, 0.007)
        k.tube('MirrorArm', [(x, 2.28, 2.1), (side * 1.42, 2.33, 2.15)], 0.03, m['trim'], root)
        k.box('TruckMirror', (side * 1.45, 2.36, 2.12), (0.18, 0.16, 0.46), m['trim'], root, 0.06)
        k.box('TruckMirrorGlass', (side * 1.45, 2.27, 2.12), (0.135, 0.018, 0.36), m['metal'], root, 0.02)
        for y in [1.87, -1.63]: wheel(root, side * 1.13, y, 0.55, 0.54, m, ('Wheel_R' if side > 0 else 'Wheel_L') + ('F' if y > 0 else 'R'))
        for center_y in [-2.05, -0.35]:
            k.box('RecessedEquipmentShutter', (side * 1.18, center_y, 1.93), (0.018, 1.36, 1.35), m['metal'], root, 0.025)
            for i in range(15): k.box('ShutterSlat', (side * 1.197, center_y, 1.32 + i * 0.087), (0.012, 1.30, 0.014), m['trim'], root, 0.004)
            k.box('ShutterLatch', (side * 1.21, center_y, 1.31), (0.03, 0.35, 0.045), m['metal'], root, 0.01)
        k.box('ReflectiveBodyStripe', (side * 1.192, -1.05, 0.94), (0.013, 3.6, 0.11), m['yellow'], root, 0.008)
        k.box('EquipmentStep', (side * 1.23, -0.8, 0.73), (0.18, 3.6, 0.09), m['metal'], root, 0.025)
    k.box('CabFrontGrille', (0, 2.97, 1.08), (1.80, 0.11, 0.38), m['trim'], root, 0.07)
    for x in [-0.7, 0.7]:
        k.box('TruckHeadlamp', (x, 2.91, 1.38), (0.43, 0.16, 0.18), m['lamp'], root, 0.03)
        k.box('TruckRearLamp', (x, -3.05, 0.96), (0.24, 0.06, 0.36), m['tail'], root, 0.035)
    k.box('TruckFrontPlate', (0, 3.064, 0.87), (0.5, 0.025, 0.13), m['yellow'], root, 0.01)
    for x in [-0.73, 0.73]: k.box('RoofBeacon', (x, 2.09, 3.01), (0.34, 0.45, 0.15), m['beacon'], root, 0.055)
    # Roof ladder with actual rungs, hose reels and rear pump fittings.
    for x in [-0.48, 0.48]: k.tube('RoofLadderRail', [(x, -2.79, 3.01), (x, 0.53, 3.01)], 0.037, m['metal'], root)
    for i in range(13): k.tube('RoofLadderRung', [(-0.48, -2.70 + i * 0.26, 3.01), (0.48, -2.70 + i * 0.26, 3.01)], 0.026, m['metal'], root)
    k.box('PumpPanel', (0, -3.075, 1.62), (1.30, 0.025, 0.78), m['trim'], root, 0.03)
    for x in [-0.4, 0, 0.4]:
        k.cylinder('PumpCoupling', (x, -3.13, 1.47), 0.095, 0.16, m['metal'], root, (0, 1, 0))
        k.cylinder('PumpGauge', (x, -3.1, 1.79), 0.062, 0.04, m['lamp'], root, (0, 1, 0))
    for x in [-0.73, 0.73]:
        k.cylinder('HoseReel', (x, -2.32, 2.96), 0.25, 0.33, m['yellow'], root, (1, 0, 0))
    k.label('ApplianceName', 'SCENE 112', (0, 2.987, 1.055), 0.13, m['white'], root, (math.pi / 2, 0, math.pi))
    join_children(root, 'FireApplianceDetails')
    k.finish(root, OUT, 'fire_truck', 8, 3.2)


police_car()
fire_truck()
