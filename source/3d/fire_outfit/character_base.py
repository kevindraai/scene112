"""Original rigged SCENE112 adults, authored geometry/PBR/animation in Blender.

Metric humans, fitted garments and original facial features; no purchased scans,
no downloaded character kit, and no conversion of the prior gameplay primitives.
"""
from pathlib import Path
import sys
import math
import bpy
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
import assetkit as k

BASE = Path(__file__).resolve().parents[3]
TEX = BASE / 'assets/textures/fire_outfit'
OUT = BASE / 'assets/models/characters'
PARTS = []


def skin(obj, bone, weights=None):
    PARTS.append(obj)
    if weights is None:
        group = obj.vertex_groups.new(name=bone)
        group.add(list(range(len(obj.data.vertices))), 1.0, 'REPLACE')
    else:
        groups = {name: obj.vertex_groups.new(name=name) for name in weights}
        for vertex in obj.data.vertices:
            at = obj.matrix_world @ vertex.co
            values = {name: fn(at) for name, fn in weights.items()}
            total = max(sum(values.values()), .001)
            for name, value in values.items():
                if value > .0001: groups[name].add([vertex.index], value / total, 'REPLACE')
    return obj


def ringbody(name, sections, mat, root, bone, count=24, weights=None):
    # Elliptical anatomical cross-sections, rounded by one Catmull-Clark pass.
    vertices = []
    for z, cx, cy, rx, ry in sections:
        vertices += [(cx + math.cos(i * math.tau / count) * rx,
                      cy + math.sin(i * math.tau / count) * ry, z) for i in range(count)]
    faces = [tuple(range(count - 1, -1, -1))]
    for layer in range(len(sections) - 1):
        for i in range(count):
            faces.append((layer * count + i, layer * count + (i + 1) % count,
                          (layer + 1) * count + (i + 1) % count, (layer + 1) * count + i))
    faces.append(tuple((len(sections) - 1) * count + i for i in range(count)))
    obj = k.mesh(name, vertices, faces, mat, root)
    mod = obj.modifiers.new('Authored anatomical contours', 'SUBSURF')
    mod.levels = 1
    mod.render_levels = 1
    k.apply(obj, mod)
    k.uv(obj)
    return skin(obj, bone, weights)


def limb(name, points, radii, mat, root, bone, weights=None):
    # Cross-sections perpendicular to the articulated limb's neutral direction.
    axis = (Vector(points[-1]) - Vector(points[0])).normalized()
    normal = axis.cross(Vector((0, 1, 0))).normalized()
    other = axis.cross(normal).normalized()
    vertices = []
    count = 16
    for at, radius in zip(points, radii):
        for i in range(count):
            a = i * math.tau / count
            v = Vector(at) + normal * math.cos(a) * radius[0] + other * math.sin(a) * radius[1]
            vertices.append(v)
    faces = [tuple(range(count - 1, -1, -1))]
    for layer in range(len(points) - 1):
        for i in range(count):
            faces.append((layer * count + i, layer * count + (i + 1) % count,
                          (layer + 1) * count + (i + 1) % count, (layer + 1) * count + i))
    faces.append(tuple((len(points) - 1) * count + i for i in range(count)))
    obj = k.mesh(name, vertices, faces, mat, root)
    mod = obj.modifiers.new('Tailored sleeve contours', 'SUBSURF')
    mod.levels = 1
    k.apply(obj, mod)
    k.uv(obj)
    return skin(obj, bone, weights)


def sphere(name, at, scale, mat, root, bone, segments=16, rings=10):
    return skin(k.sphere(name, at, scale, mat, root, segments, rings), bone)


def box(name, at, size, mat, root, bone, radius=.008):
    return skin(k.box(name, at, size, mat, root, radius), bone)


def tube(name, points, radius, mat, root, bone):
    return skin(k.tube(name, points, radius, mat, root), bone)


def materials(police):
    return {
        'skin': k.material('officer_skin' if police else 'civilian_skin', (.49, .275, .185) if police else (.62, .41, .295), .63, 0, TEX, 'skin'),
        'lip': k.material('natural_lip', (.32, .125, .105), .65),
        'hair': k.material('short_hair', (.023, .019, .016) if police else (.105, .055, .025), .83),
        'eye': k.material('eye_white', (.80, .83, .81), .30),
        'iris': k.material('iris', (.055, .16, .12) if police else (.15, .078, .028), .32),
        'pupil': k.material('pupil', (.006, .008, .007), .25),
        'top': k.material('police_navy_cloth' if police else 'civilian_sage_cloth', (.018, .052, .089) if police else (.14, .19, .115), .89, 0, TEX, 'fabric'),
        'pants': k.material('police_trouser_cloth' if police else 'civilian_denim', (.028, .036, .048) if police else (.036, .075, .125), .91, 0, TEX, 'fabric'),
        'rubber': k.material('duty_boot_rubber' if police else 'trainer_rubber', (.025, .025, .029), .87, 0, TEX, 'rubber'),
        'leather': k.material('duty_boot_upper' if police else 'trainer_upper', (.032, .042, .041) if police else (.16, .12, .085), .57, 0, TEX, 'rubber'),
        'trim': k.material('clothing_seam', (.008, .014, .02), .86),
        'accent': k.material('officer_amber_detail' if police else 'civilian_jacket_trim', (.85, .67, .13) if police else (.32, .29, .20), .50),
        'metal': k.material('brushed_fastener', (.35, .39, .41), .35, .8),
        'badge': k.material('original_112_badge', (.63, .66, .63), .38, .28)
    }


def face(root, m, police):
    ringbody('AdultHead', [(1.505,0,-.015,.045,.055),(1.535,0,-.014,.074,.072),
        (1.57,0,-.014,.092,.09),(1.63,0,-.014,.112,.107),(1.69,0,-.025,.113,.107),
        (1.76,0,-.026,.105,.102),(1.81,0,-.026,.075,.078),(1.834,0,-.026,.014,.023)],m['skin'],root,'Head')
    ringbody('Neck',[(1.425,0,-.003,.05,.045),(1.50,0,-.008,.047,.046),(1.56,0,-.014,.055,.052)],m['skin'],root,'Neck',24)
    for side in [-1,1]:
        x=side*.046
        sphere('EyeSocket', (x,.081,1.685),(.022,.010,.010),m['lip'],root,'Head')
        sphere('EyeWhite',(x,.089,1.684),(.018,.007,.0065),m['eye'],root,'Head')
        sphere('Iris',(x,.095,1.684),(.006,.0018,.006),m['iris'],root,'Head')
        sphere('Pupil',(x,.0965,1.684),(.003,.001,.004),m['pupil'],root,'Head')
        tube('UpperEyelid',[(x-.018,.091,1.684),(x-.011,.093,1.690),(x+.007,.093,1.691),(x+.018,.09,1.685)],.003,m['skin'],root,'Head')
        tube('Brow',[(x-.029,.080,1.714),(x-.012,.086,1.718),(x+.012,.087,1.718),(x+.029,.077,1.710)],.004,m['hair'],root,'Head')
        sphere('Ear',(side*.113,-.025,1.671),(.017,.026,.039),m['skin'],root,'Head')
        tube('EarFold',[(side*.126,-.037,1.646),(side*.130,-.007,1.657),(side*.128,-.007,1.688),(side*.125,-.028,1.701)],.0035,m['lip'],root,'Head')
        sphere('NostrilWing',(side*.014,.102,1.633),(.011,.011,.008),m['skin'],root,'Head')
        sphere('NostrilShadow',(side*.013,.108,1.628),(.0045,.002,.0025),m['lip'],root,'Head',16,8)
    nose=k.mesh('SculptedNose',[(-.012,.080,1.702),(.012,.080,1.702),(-.016,.093,1.630),(.016,.093,1.630),(0,.123,1.642),(0,.087,1.713)],
        [(0,1,5),(0,2,4),(0,4,5),(5,4,1),(1,4,3),(2,3,4)],m['skin'],root)
    mod=nose.modifiers.new('Nose contour','SUBSURF');mod.levels=2;k.apply(nose,mod);skin(nose,'Head')
    tube('UpperLip',[(-.027,.080,1.595),(-.014,.089,1.598),(0,.09,1.597),(.012,.089,1.598),(.027,.080,1.595)],.004,m['lip'],root,'Head')
    tube('LowerLip',[(-.025,.083,1.589),(0,.091,1.586),(.025,.083,1.589)],.004,m['lip'],root,'Head')
    tube('MouthLine',[(-.025,.087,1.594),(0,.092,1.593),(.025,.087,1.594)],.0015,m['hair'],root,'Head')
    # Hairstyle authored as cap following the crown with individual hair grooves.
    ringbody('HairContour',[(1.742,0,-.044,.110,.091),(1.779,0,-.034,.101,.10),(1.820,0,-.033,.063,.065),(1.842,0,-.032,.008,.016)],m['hair'],root,'Head')
    for i in range(-5,6):
        x=i*.014
        tube('HairPart',[(x,-.100,1.776),(x-.008,-.039,1.835),(x-.010,.035,1.795)],.0018,m['trim'],root,'Head')
    if police:
        ringbody('UniformCap',[(1.766,0,-.020,.118,.108),(1.805,0,-.020,.122,.107),(1.845,0,-.020,.089,.087),(1.854,0,-.020,.025,.03)],m['top'],root,'Head')
        brim=k.mesh('CurvedCapBrim',[(-.10,.040,1.787),(.10,.040,1.787),(.105,.110,1.769),(.070,.174,1.745),(0,.184,1.742),(-.07,.174,1.745),(-.105,.110,1.769)],[(0,1,2,3,4,5,6)],m['top'],root)
        solid=brim.modifiers.new('Brim thickness','SOLIDIFY');solid.thickness=.004;k.apply(brim,solid);skin(brim,'Head')
        badge=k.label('OriginalCap112','112',(0,.090,1.802),.027,m['badge'],root,(math.pi/2,0,math.pi));skin(badge,'Head')


def body(root,m,police):
    torso_sections=[(.875,0,0,.129,.084),(.97,0,.002,.145,.088),(1.04,0,.001,.130,.082),
      (1.14,0,-.005,.151,.10),(1.28,0,-.003,.179,.11),(1.365,0,-.003,.205,.101),
      (1.403,0,-.003,.190,.087),(1.436,0,-.007,.13,.063),(1.450,0,-.009,.062,.046)]
    weights={'Pelvis':lambda p:max(0,1-abs(p.z-.91)/.18),'Spine':lambda p:max(0,1-abs(p.z-1.13)/.21), 'Chest':lambda p:max(0,1-abs(p.z-1.40)/.28)}
    ringbody('TailoredUniform' if police else 'FittedJacket',torso_sections,m['top'],root,'Chest',weights=weights)
    ringbody('TrouserSeat',[(.845,0,0,.135,.083),(.89,0,0,.151,.09),(.973,0,0,.143,.087)],m['pants'],root,'Pelvis')
    # Open neck, zipper pull, collar sides, seams and fabric hem.
    for side in [-1,1]:
        collar=k.mesh('RaisedCollar',[(side*.03,.038,1.456),(side*.065,.014,1.435),(side*.073,.067,1.404),(side*.020,.076,1.411)],[(0,1,2,3)],m['top'],root)
        skin(collar,'Chest')
        tube('ShoulderSeam',[(side*.068,-.037,1.434),(side*.160,-.03,1.412),(side*.209,-.024,1.379)],.0028,m['trim'],root,'Chest')
        tube('JacketFrontSeam',[(side*.115,.066,1.375),(side*.126,.093,1.20),(side*.114,.075,1.045)],.0018,m['trim'],root,'Spine')
    tube('ZipSeam',[(0,.047,1.426),(0,.097,1.30),(0,.099,1.18),(0,.082,1.03)],.003,m['trim'],root,'Chest')
    box('ZipperPull',(0,.103,1.292),(.007,.005,.026),m['metal'],root,'Chest',.002)
    # A real cloth cuff and continuous weighted knee eliminate disconnected joints.
    for side,tag in [(-1,'L'),(1,'R')]:
        x=side*.105
        legsections=[(.101,x,0,.042,.045),(.15,x,0,.050,.053),(.29,x,-.010,.058,.063),
            (.465,x,.002,.060,.067),(.525,x,.009,.064,.072),(.69,x,0,.077,.086),(.84,x,-.002,.080,.093),(.907,x,-.003,.076,.089)]
        weights={tag+'Thigh':lambda p:min(1,max(0,(p.z-.425)/.18)),tag+'Shin':lambda p:1-min(1,max(0,(p.z-.425)/.18))}
        ringbody('FittedTrouserLeg'+tag,legsections,m['pants'],root,tag+'Thigh',weights=weights)
        # Slight trouser crease follows the front of the leg with joint weights.
        seam=k.tube('TrouserCrease'+tag,[(x,.093,.858),(x,.088,.70),(x,.077,.515),(x,.059,.30),(x,.045,.15)],.0014,m['trim'],root)
        skin(seam,tag+'Thigh',weights)
        shoe=ringbody('LeatherDutyBoot'+tag if police else 'LeatherTrainer'+tag,[(.033,x,.05,.059,.14),(.061,x,.057,.062,.151),(.105,x,.052,.061,.14),(.145,x,.004,.049,.064),(.175,x,-.005,.046,.050)],m['leather'],root,tag+'Foot')
        ringbody('Outsole'+tag,[(.006,x,.047,.058,.140),(.013,x,.052,.067,.157),(.042,x,.052,.068,.155),(.052,x,.052,.062,.148)],m['rubber'],root,tag+'Foot')
        for z,y in [(.111,.086),(.12,.059),(.133,.032)]:
            tube('BootLace'+tag,[(x-.038,y,z),(x+.038,y,z+.003)],.002,m['trim'],root,tag+'Foot')
        # Tailored sleeve, continuous weights from upper arm into forearm.
        points=[(side*.183,-.002,1.385),(side*.225,0,1.374),(side*.283,.003,1.274),(side*.352,.013,1.129),(side*.376,.022,1.065),(side*.405,.038,.925),(side*.413,.044,.890)]
        weights={tag+'UpperArm':lambda p:min(1,max(0,(p.z-1.065)/.12)),tag+'ForeArm':lambda p:1-min(1,max(0,(p.z-1.065)/.12))}
        limb('TailoredSleeve'+tag,points,[(.054,.067),(.073,.067),(.062,.059),(.052,.050),(.046,.045),(.037,.037),(.038,.038)],m['top'],root,tag+'UpperArm',weights)
        sphere('SleeveCuff'+tag,(side*.411,.043,.909),(.04,.04,.019),m['trim'],root,tag+'ForeArm')
        sphere('HandPalm'+tag,(side*.418,.052,.851),(.036,.025,.051),m['skin'],root,tag+'Hand')
        for finger in range(4):
            fx=side*(.396+finger*.014)
            endz=.764+abs(finger-1.4)*.011
            limb('Finger'+tag+str(finger),[(fx,.061,.829),(fx,.066,.799),(fx,.07,endz)],[(.009,.009),(.008,.008),(.005,.005)],m['skin'],root,tag+'Hand')
            sphere('Fingernail'+tag+str(finger),(fx,.075,endz+.006),(.005,.0018,.006),m['badge'],root,tag+'Hand',16,8)
        limb('Thumb'+tag,[(side*.389,.053,.869),(side*.373,.067,.839),(side*.371,.076,.818)],[(.013,.011),(.010,.009),(.006,.006)],m['skin'],root,tag+'Hand')
        if police:
            # Subtle original amber markings, not an official police livery.
            band=sphere('UpperArmAmberBand'+tag,(side*.277,.004,1.285),(.064,.061,.018),m['accent'],root,tag+'UpperArm')
    if police:
        ringbody('DutyBelt',[(.965,0,0,.145,.092),(.993,0,0,.145,.092)],m['leather'],root,'Pelvis')
        box('BeltBuckle',(0,.096,.982),(.045,.010,.033),m['metal'],root,'Pelvis')
        box('OriginalPatch',(-.09,.103,1.319),(.063,.006,.056),m['trim'],root,'Chest',.004)
        badge=k.label('Chest112','112',(-.09,.108,1.306),.028,m['badge'],root,(math.pi/2,0,math.pi));skin(badge,'Chest')
        box('ChestRadio',(.104,.117,1.27),(.057,.035,.089),m['trim'],root,'Chest',.008)
        tube('RadioAntenna',[(.10,.12,1.309),(.10,.12,1.373)],.003,m['trim'],root,'Chest')
        tube('RadioMicCable',[(.09,.122,1.29),(.11,.113,1.364),(.07,.101,1.392)],.003,m['trim'],root,'Chest')
        box('MicClip',(.07,.106,1.394),(.031,.012,.036),m['trim'],root,'Chest')
        for side in [-1,1]:
            box('UtilityPouch',(side*.148,.025,.973),(.064,.081,.102),m['leather'],root,'Pelvis',.010)
        tube('ChestAccent',[(-.139,.086,1.363),(-.040,.103,1.363),(.020,.103,1.363)],.004,m['accent'],root,'Chest')
    else:
        for side in [-1,1]:
            box('JacketPocket',(side*.102,.098,1.14),(.068,.006,.09),m['top'],root,'Spine',.006)
            tube('PocketBinding',[(side*.07,.103,1.187),(side*.13,.103,1.187)],.002,m['accent'],root,'Spine')


def rig(root):
    data=bpy.data.armatures.new('Scene112HumanRig')
    arm=bpy.data.objects.new('HumanRig',data)
    bpy.context.collection.objects.link(arm)
    k.parent(arm,root)
    bpy.context.view_layer.objects.active=arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    specs=[('Root',(0,0,0),(0,0,.20),None),('Pelvis',(0,0,.89),(0,0,1.02),'Root'),
        ('Spine',(0,0,1.02),(0,0,1.28),'Pelvis'),('Chest',(0,0,1.28),(0,0,1.445),'Spine'),
        ('Neck',(0,0,1.445),(0,0,1.56),'Chest'),('Head',(0,0,1.56),(0,0,1.825),'Neck')]
    for side,tag in [(-1,'L'),(1,'R')]:
        specs += [(tag+'Thigh',(side*.105,0,.92),(side*.105,.009,.515),'Pelvis'),
          (tag+'Shin',(side*.105,.009,.515),(side*.105,0,.115),tag+'Thigh'),
          (tag+'Foot',(side*.105,0,.115),(side*.105,.19,.055),tag+'Shin'),
          (tag+'UpperArm',(side*.20,0,1.39),(side*.352,.013,1.129),'Chest'),
          (tag+'ForeArm',(side*.352,.013,1.129),(side*.413,.044,.89),tag+'UpperArm'),
          (tag+'Hand',(side*.413,.044,.89),(side*.418,.065,.79),tag+'ForeArm')]
    for name,head,tail,parentname in specs:
        b=data.edit_bones.new(name);b.head=head;b.tail=tail
        if parentname:b.parent=data.edit_bones[parentname]
    bpy.ops.object.mode_set(mode='OBJECT')
    arm.select_set(False)
    # Consolidate all authored parts into one skinned render mesh with source UVs.
    bpy.ops.object.select_all(action='DESELECT')
    for obj in PARTS:obj.select_set(True)
    bpy.context.view_layer.objects.active=PARTS[0]
    bpy.ops.object.join()
    mesh=bpy.context.object;mesh.name='SkinnedAdultSurface'
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    k.parent(mesh,arm)
    deform=mesh.modifiers.new('Scene112 bone deformation','ARMATURE');deform.object=arm
    mesh.select_set(False)
    return arm


def animate(arm):
    arm.animation_data_create()
    bpy.context.scene.render.fps=30
    for name,length in [('idle',90),('walk',48),('run',24),('carry',48)]:
        action=bpy.data.actions.new(name);action.use_fake_user=True
        arm.animation_data.action=action
        for frame in range(0,length+1,2):
            phase=frame/length*math.tau
            for p in arm.pose.bones:
                p.rotation_mode='XYZ';p.rotation_euler=(0,0,0);p.location=(0,0,0)
            if name=='idle':
                arm.pose.bones['Chest'].rotation_euler.x=.012*math.sin(phase)
                arm.pose.bones['Head'].rotation_euler.z=.025*math.sin(phase)
                arm.pose.bones['LForeArm'].rotation_euler.x=-.05
                arm.pose.bones['RForeArm'].rotation_euler.x=-.05
            else:
                amp=.43 if name!='run' else .75
                for tag,offset in [('L',0),('R',math.pi)]:
                    s=math.sin(phase+offset)
                    arm.pose.bones[tag+'Thigh'].rotation_euler.x=amp*s
                    arm.pose.bones[tag+'Shin'].rotation_euler.x=-max(0,-s)*(.68 if name!='run' else 1.05)
                    arm.pose.bones[tag+'Foot'].rotation_euler.x=.12*math.sin(phase+offset+.5)
                    arm.pose.bones[tag+'UpperArm'].rotation_euler.x=-amp*.65*s
                    arm.pose.bones[tag+'ForeArm'].rotation_euler.x=-.22 if name!='run' else -.6
                arm.pose.bones['Pelvis'].location.y=.012*abs(math.sin(phase))
                arm.pose.bones['Spine'].rotation_euler.y=.035*math.sin(phase)
                arm.pose.bones['Chest'].rotation_euler.y=-.045*math.sin(phase)
                if name=='run':arm.pose.bones['Spine'].rotation_euler.x=.09
                if name=='carry':
                    for tag in ['L','R']:
                        arm.pose.bones[tag+'UpperArm'].rotation_euler.x=.70
                        arm.pose.bones[tag+'ForeArm'].rotation_euler.x=-1.0
            for p in arm.pose.bones:
                p.keyframe_insert(data_path='rotation_euler',frame=frame,group=p.name)
                if p.name=='Pelvis':p.keyframe_insert(data_path='location',frame=frame,group=p.name)
        for curve in action.fcurves:
            for key in curve.keyframe_points:key.interpolation='LINEAR'
        track=arm.animation_data.nla_tracks.new();track.name=name
        strip=track.strips.new(name,0,action);strip.action_frame_start=0;strip.action_frame_end=length
        track.mute=True
    arm.animation_data.action=None
    # Neutral authored preview while retaining all NLA action clips for GLB.
    for p in arm.pose.bones:p.rotation_euler=(0,0,0);p.location=(0,0,0)
    bpy.context.scene.frame_set(0)

