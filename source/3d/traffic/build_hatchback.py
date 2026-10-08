"""Original compact five-door civilian hatchback for SCÈNE112 traffic.

No reference model/real brand/asset kit. Metric Blender +Y forward becomes
Godot -Z forward. Four shared PBR materials, real axle roots, packed source.
"""
from pathlib import Path
import math
import sys
import json
import hashlib
import bpy
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
import assetkit as k

BASE = Path(__file__).resolve().parents[3]
TEX = BASE / 'assets/textures/traffic'
OUT = BASE / 'assets/models/traffic'
RADIUS = .315
WHEEL_X = .755
FRONT_AXLE = 1.09
REAR_AXLE = -1.12


def color(obj, rgba):
    attribute = obj.data.color_attributes.get('SurfaceTint')
    if attribute is None:
        attribute = obj.data.color_attributes.new(name='SurfaceTint', type='FLOAT_COLOR', domain='CORNER')
    obj.data.color_attributes.active_color = attribute
    obj.data.color_attributes.render_color_index = obj.data.color_attributes.find('SurfaceTint')
    for corner in attribute.data: corner.color = (*rgba[:3], rgba[3] if len(rgba) > 3 else 1)
    return obj


def materials():
    m = {
        'paint': k.material('traffic_bluegray_paint', (.15, .235, .285), .31, .36, TEX),
        'trim': k.material('traffic_rubber_polymer', (.027, .033, .038), .76, .0, TEX, 'rubber'),
        'metal': k.material('traffic_alloy_lenses', (.68, .70, .72), .31, .48, TEX),
        'glass': k.material('traffic_automotive_glass', (.16, .235, .265), .12, .08, alpha=.22)}
    # A single opaque PBR surface shares rims and lens/plate details using
    # authored vertex tints, keeping the entire vehicle at four materials.
    material = m['metal']
    shader = material.node_tree.nodes.get('Principled BSDF')
    texture = next(link.from_node for link in material.node_tree.links if link.to_socket == shader.inputs['Base Color'])
    for link in list(material.node_tree.links):
        if link.to_socket == shader.inputs['Base Color']: material.node_tree.links.remove(link)
    vertex = material.node_tree.nodes.new('ShaderNodeVertexColor')
    vertex.layer_name = '' # Active render-color layer is glTF's COLOR_0.
    # Blender's material graph supplies its own authoring preview; glTF's
    # ACTIVE export deliberately applies the same COLOR_0 to every primitive.
    multiply = material.node_tree.nodes.new('ShaderNodeMixRGB')
    multiply.blend_type = 'MULTIPLY'
    multiply.inputs[0].default_value = 1.0
    material.node_tree.links.new(texture.outputs['Color'], multiply.inputs[1])
    material.node_tree.links.new(vertex.outputs['Color'], multiply.inputs[2])
    material.node_tree.links.new(multiply.outputs[0], shader.inputs['Base Color'])
    return m


def join_children(root, name):
    meshes = [obj for obj in root.children if obj.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes: obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    mesh = bpy.context.object
    mesh.name = name
    # glTF's standard material reads COLOR_0. Keep the actual authored layer
    # active through joins rather than exporting a generated white COLOR_0.
    attributes = mesh.data.color_attributes
    if attributes.get('SurfaceTint') is not None:
        for attribute in list(attributes):
            if attribute.name != 'SurfaceTint': attributes.remove(attribute)
        attributes.active_color = attributes.get('SurfaceTint')
        attributes.render_color_index = 0
    mesh.select_set(False)
    return mesh


def loft(root, material):
    # Rounded asymmetric nose/hatch shoulders; authored longitudinal profile.
    sections = [(-1.83,.695,.30,.80), (-1.62,.795,.26,.94),
                (-1.10,.845,.235,1.00), (-.38,.860,.235,1.00),
                (.54,.845,.24,.96), (1.11,.811,.27,.865),
                (1.64,.735,.31,.775), (1.83,.644,.37,.674)]
    vertices = []
    for y, width, low, top in sections:
        outline = [(-width*.87,low),(width*.87,low),(width,low+.10),
                   (width,top-.10),(width*.88,top),(-width*.88,top),
                   (-width,top-.10),(-width,low+.10)]
        vertices.extend((x,y,z) for x,z in outline)
    faces = [tuple(range(7,-1,-1))]
    for index in range(len(sections)-1):
        for point in range(8):
            faces.append((index*8+point,index*8+(point+1)%8,
                          (index+1)*8+(point+1)%8,(index+1)*8+point))
    faces.append(tuple((len(sections)-1)*8+i for i in range(8)))
    body = k.mesh('Original rounded body', vertices, faces, material, root, .025)
    for y in [FRONT_AXLE, REAR_AXLE]:
        bpy.ops.mesh.primitive_cylinder_add(vertices=16 if k.LOW_DETAIL else 32, radius=.36, depth=2.2,
            location=(0,y,RADIUS), rotation=(0,math.pi/2,0))
        cut = bpy.context.object
        modifier = body.modifiers.new('Actual curved wheel clearance','BOOLEAN')
        modifier.operation = 'DIFFERENCE'
        modifier.solver = 'EXACT'
        modifier.object = cut
        k.apply(body,modifier)
        bpy.data.objects.remove(cut,do_unlink=True)
    k.bevel(body,.008,1)
    k.uv(body)
    return body


def roof(root, material):
    vertices = []
    rows = [(-1.08,.605,1.365),(-.80,.671,1.475),(-.23,.686,1.515),
            (.27,.648,1.472),(.49,.585,1.372)]
    for y,width,z in rows:
        vertices.extend([(-width,y,z-.045),(-width*.72,y,z),
                         (width*.72,y,z),(width,y,z-.045)])
    faces = []
    for row in range(len(rows)-1):
        for point in range(3): faces.append((row*4+point,row*4+point+1,(row+1)*4+point+1,(row+1)*4+point))
    mesh = k.mesh('Authored shallow curved roof',vertices,faces,material,root)
    solid = mesh.modifiers.new('Real roof skin','SOLIDIFY');solid.thickness=.025;k.apply(mesh,solid)
    k.bevel(mesh,.009,2)
    return mesh


def window(root, name, corners, m):
    mesh = k.mesh(name,corners,[(0,1,2,3)],m['glass'],root)
    solid = mesh.modifiers.new('Thin actual glazing','SOLIDIFY');solid.thickness=.006;k.apply(mesh,solid)
    k.tube(name+' gasket',corners+[corners[0]],.015,m['trim'],root)
    return mesh


def cabin(root,m):
    roof(root,m['paint'])
    windshield = [(-.767,.886,.973),(.767,.886,.973),(.638,.378,1.421),(-.638,.378,1.421)]
    rear = [(-.653,-.867,1.443),(.653,-.867,1.443),(.766,-1.583,1.012),(-.766,-1.583,1.012)]
    window(root,'Broad windscreen',windshield,m)
    window(root,'Sloping hatch glass',rear,m)
    for side in [-1,1]:
        front = [(side*.806,.872,.984),(side*.851,-.10,1.004),
                 (side*.679,-.10,1.465),(side*.639,.375,1.421)]
        back = [(side*.850,-.192,1.0),(side*.808,-1.234,.985),
                (side*.654,-.822,1.444),(side*.679,-.186,1.465)]
        window(root,'Front door glazing',front,m);window(root,'Rear door glazing',back,m)
        k.tube('A pillar',[(side*.771,.901,.967),(side*.644,.392,1.423)],.032,m['paint'],root)
        k.tube('B pillar',[(side*.852,-.146,.980),(side*.676,-.146,1.477)],.032,m['trim'],root)
        k.tube('Swept C pillar',[(side*.811,-1.288,.968),(side*.661,-.875,1.454)],.043,m['paint'],root)
        for points in [[(side*.847,.84,.92),(side*.865,.69,.42),(side*.865,-.143,.41),(side*.850,-.143,.97)],
                       [(side*.853,-.20,.97),(side*.865,-.20,.42),(side*.838,-1.14,.45),(side*.809,-1.28,.98)]]:
            k.tube('Pressed door panel gap',points,.0055,m['trim'],root)
        for y in [.02,-.73]:
            color(k.box('Flush pull handle',(side*.858,y,.941),(.024,.13,.024),m['metal'],root,.007),(.30,.33,.36,1))
        k.tube('Mirror support',[(side*.813,.66,1.037),(side*.936,.643,1.100)],.018,m['trim'],root)
        k.sphere('Compact mirror housing',(side*.917,.636,1.107),(.088,.071,.051),m['paint'],root,16,8)
        color(k.box('Mirror reflection',(side*.917,.574,1.108),(.150,.007,.068),m['metal'],root,.006),(.76,.82,.85,1))
    # Actual interior, bounded for ambient traffic rather than an enterable car.
    k.box('Cabin floor',(0,-.22,.41),(1.43,2.15,.05),m['trim'],root,.01)
    dash = k.box('Shaped dashboard',(0,.57,.924),(1.35,.27,.16),m['trim'],root,.045)
    for x in [-.34,.34]:
        k.box('Front seat cushion',(x,-.03,.637),(.45,.43,.14),m['trim'],root,.047)
        back = k.box('Front seat back',(x,-.246,.902),(.435,.115,.52),m['trim'],root,.047)
        back.rotation_euler.x = -.15
        k.box('Front head restraint',(x,-.260,1.206),(.23,.095,.125),m['trim'],root,.032)
    k.box('Rear bench seat',(0,-.858,.636),(1.13,.38,.14),m['trim'],root,.041)
    k.box('Rear bench back',(0,-1.099,.857),(1.12,.105,.40),m['trim'],root,.037)
    k.box('Rear parcel shelf',(0,-1.31,.88),(1.31,.30,.028),m['trim'],root,.009)
    center = Vector((-.34,.42,1.08))
    steering = [(center.x+math.cos(i*math.tau/20)*.143,center.y,
                 center.z+math.sin(i*math.tau/20)*.143) for i in range(21)]
    k.tube('Steering wheel',steering,.016,m['trim'],root)
    for angle in [0,2.1,4.2]:
        k.tube('Steering spoke',[(center.x,center.y,center.z),
            (center.x+math.cos(angle)*.12,center.y,center.z+math.sin(angle)*.12)],.011,m['trim'],root)


def details(root,m):
    k.box('Lower front intake',(0,1.842,.432),(.925,.018,.075),m['trim'],root,.012)
    for x in [-.32,0,.32]:k.box('Intake vertical louvre',(x,1.855,.432),(.016,.009,.057),m['trim'],root,.002)
    for side in [-1,1]:
        # Flush clusters on the nose, not floating blocks on the bonnet.
        color(k.box('Front optical lens',(side*.485,1.840,.613),(.295,.018,.117),m['metal'],root,.016),(.90,.93,.90,1))
        color(k.box('Amber indicator',(side*.617,1.847,.601),(.040,.015,.065),m['metal'],root,.009),(.97,.39,.021,1))
        color(k.box('Red rear lens',(side*.50,-1.840,.699),(.255,.018,.139),m['metal'],root,.017),(.90,.032,.015,1))
        color(k.box('Rear reverse insert',(side*.50,-1.852,.665),(.09,.013,.031),m['metal'],root,.007),(.80,.86,.88,1))
        k.tube('Lower sill trim',[(side*.844,-.94,.299),(side*.850,.875,.296)],.022,m['trim'],root)
    for y,z,rotation in [(1.845,.510,(math.pi/2,0,math.pi)),(-1.842,.490,(math.pi/2,0,0))]:
        k.box('Plate surround',(0,y,z),(.465,.015,.103),m['trim'],root,.012)
        plate=color(k.box('Fictional Dutch yellow plate',(0,y+( .012 if y>0 else -.012),z),(.435,.007,.083),m['metal'],root,.008),(.95,.63,.015,1))
        text=k.label('Fictional registration','NK-026',(0,y+(.017 if y>0 else -.017),z-.013),.046,m['trim'],root,rotation)
        k.uv(text)
    k.tube('Hatch wiper',[(.28,-1.608,1.046),(-.15,-1.393,1.199)],.010,m['trim'],root)
    k.tube('Front wiper left',[(-.52,.906,.994),(-.20,.662,1.200)],.009,m['trim'],root)
    k.tube('Front wiper right',[(.08,.906,.994),(.45,.670,1.194)],.009,m['trim'],root)
    k.tube('Short roof antenna',[(0,-.66,1.49),(0,-.73,1.68)],.006,m['trim'],root)
    k.tube('Hatch seam',[(-.77,-1.70,.79),(-.76,-1.592,.995),(-.65,-.87,1.438),
                       (.65,-.87,1.438),(.76,-1.592,.995),(.77,-1.70,.79)],.005,m['trim'],root)
    k.box('Hatch recessed grip',(0,-1.820,.695),(.178,.014,.029),m['trim'],root,.009)
    k.box('Undertray',(0,0,.247),(1.36,3.15,.072),m['trim'],root,.016)


def wheel(root,x,y,name,m):
    axle=k.empty(name,(x,y,RADIUS));k.parent(axle,root)
    # Original 32-slice lathed tyre: no stacked tread-box geometry.
    count=20 if k.LOW_DETAIL else 32; half=.087
    profile=[(-1,.64),(-1,.81),(-.84,.955),(-.54,1),(.54,1),(.84,.955),(1,.81),(1,.64)]
    vertices=[(x+a*half,y+math.sin(i*math.tau/count)*r*RADIUS,
               RADIUS+math.cos(i*math.tau/count)*r*RADIUS) for a,r in profile for i in range(count)]
    faces=[(row*count+i,row*count+(i+1)%count,((row+1)%len(profile))*count+(i+1)%count,
            ((row+1)%len(profile))*count+i) for row in range(len(profile)) for i in range(count)]
    k.mesh('Rounded pneumatic tyre',vertices,faces,m['trim'],axle)
    side=1 if x>0 else -1
    face_x=x+side*(half+.004)
    rim=color(k.cylinder('Wheel alloy dish',(face_x,y,RADIUS),RADIUS*.65,.023,m['metal'],axle,(1,0,0),24),(.55,.58,.60,1))
    brake=color(k.cylinder('Recessed brake disc',(face_x-side*.032,y,RADIUS),RADIUS*.54,.016,m['metal'],axle,(1,0,0),20),(.22,.235,.25,1))
    for i in range(5):
        angle=i*math.tau/5
        spoke=color(k.box('Five spoke wheel',(face_x+side*.014,y+math.sin(angle)*RADIUS*.33,
                     RADIUS+math.cos(angle)*RADIUS*.33),(.030,.040,RADIUS*.45),m['metal'],axle,.009),(.84,.86,.88,1))
        spoke.rotation_euler.x=-angle
    hub=color(k.cylinder('Wheel hub',(face_x+side*.03,y,RADIUS),.052,.036,m['metal'],axle,(1,0,0),16),(.39,.42,.44,1))
    for i in range(5):
        angle=i*math.tau/5
        bolt=color(k.cylinder('Recessed wheel fastener',(face_x+side*.052,y+math.sin(angle)*.036,
                     RADIUS+math.cos(angle)*.036),.007,.007,m['metal'],axle,(1,0,0),8),(.13,.15,.17,1))
    join_children(axle,name+'Surface')
    return axle


def audit(root, name):
    meshes=[obj for obj in root.children_recursive if obj.type=='MESH']
    materials={material.name for obj in meshes for material in obj.data.materials}
    triangles=sum(sum(len(face.vertices)-2 for face in obj.data.polygons) for obj in meshes)
    print('SCENE112_TRAFFIC_MESH_COUNTS',[(obj.name,sum(len(face.vertices)-2 for face in obj.data.polygons)) for obj in meshes],flush=True)
    assert triangles<=18000,(name,triangles,'18k budget exceeded')
    assert len(materials)<=4,(name,materials,'four-material budget exceeded')
    assert len(meshes)==5,(name,'one body plus four actual wheel meshes')
    print('SCENE112_TRAFFIC_BUDGET_OK',name,triangles,len(materials),flush=True)


def build():
    for low_detail in [False,True]:
        k.clean();k.LOW_DETAIL=low_detail
        root=k.empty('CivilianHatchbackLOD' if low_detail else 'CivilianHatchback')
        m=materials()
        loft(root,m['paint']);cabin(root,m);details(root,m)
        body=join_children(root,'HatchbackBodySurface')
        for x,side in [(-WHEEL_X,'L'),(WHEEL_X,'R')]:
            for y,end in [(FRONT_AXLE,'F'),(REAR_AXLE,'R')]:wheel(root,x,y,'Wheel_'+side+end,m)
        asset='civilian_hatchback_lod' if low_detail else 'civilian_hatchback'
        audit(root,asset)
        k.finish(root,OUT,asset,4.3,1.68)
    integration={'front':'-Z','up':'+Y','units':'metres','wheel_spin_axis':'local X',
        'wheel_radius_m':RADIUS,'nodes':['Wheel_LF','Wheel_RF','Wheel_LR','Wheel_RR'],
        'front_axle_godot_z':-FRONT_AXLE,'rear_axle_godot_z':-REAR_AXLE,
        'half_track_m':WHEEL_X,'physics':'No exported colliders; root owns bounded traffic body and avoidance',
        'lod':'Separate explicitly lower-segment mesh GLB, same axle API; no decimation tie decisions, automatic LOD/core patch or hardwareperformanceclaim'}
    (OUT/'civilian_hatchback_integration.json').write_text(json.dumps(integration,indent=2)+'\n')


build()
