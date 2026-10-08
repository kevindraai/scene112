"""Original duty-building shells for existing SCÈNE112 bureau/kazerne footprints.

No exported physics, new geography or real agency branding. Public local
coordinates are Godot metres/front+Z; Blender conversion is explicit below.
"""
from pathlib import Path
import sys,math,json
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
import assetkit as k
import street_surface_fields as f

BASE=Path(__file__).resolve().parents[3]
TEX=BASE/'assets/textures/duty_buildings'
OUT=BASE/'assets/models/duty_buildings'


def point(at):return (at[0],-at[2],at[1])


def uv_metres(obj,tile):
    if obj.type!='MESH':return
    bpy.context.view_layer.update()
    for layer in list(obj.data.uv_layers):obj.data.uv_layers.remove(layer)
    uv=obj.data.uv_layers.new(name='Physical surface metres')
    obj.data.uv_layers.active_index=0;uv.active_render=True
    for face in obj.data.polygons:
        axis=max(range(3),key=lambda i:abs(face.normal[i]))
        indices=[i for i in range(3)if i!=axis]
        for index in face.loop_indices:
            at=obj.matrix_world@obj.data.vertices[obj.data.loops[index].vertex_index].co
            uv.data[index].uv=(at[indices[0]]/tile,at[indices[1]]/tile)


def tint(obj,colour):
    layer=obj.data.color_attributes.new(name='SurfaceTint',type='FLOAT_COLOR',domain='CORNER')
    for value in layer.data:value.color=(*colour,1)
    obj.data.color_attributes.active_color=layer;obj.data.color_attributes.render_color_index=0
    return obj


def group(root,name):
    obj=k.empty(name);k.parent(obj,root);return obj


def B(root,name,at,size,mat,bevel=.008,colour=None):
    obj=k.box(name,point(at),(size[0],size[2],size[1]),mat,root,bevel)
    uv_metres(obj,float(mat.get('uv_tile_m',2.0)))
    if colour is not None:tint(obj,colour)
    return obj


def M(root,name,vertices,faces,mat):
    obj=k.mesh(name,[point(at)for at in vertices],faces,mat,root)
    uv_metres(obj,float(mat.get('uv_tile_m',2.0)))
    return obj


def T(root,name,points,radius,mat):
    obj=k.tube(name,[point(at)for at in points],radius,mat,root)
    uv_metres(obj,float(mat.get('uv_tile_m',2.0)))
    return obj


def join(root,name):
    meshes=[obj for obj in root.children if obj.type=='MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes:obj.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join()
    obj=bpy.context.object;obj.name=name
    attributes=obj.data.color_attributes
    if attributes.get('SurfaceTint') is not None:
        for attribute in list(attributes):
            if attribute.name!='SurfaceTint':attributes.remove(attribute)
        attributes.active_color=attributes.get('SurfaceTint');attributes.render_color_index=0
    obj.select_set(False)
    return obj


def materials():
    TEX.mkdir(parents=True,exist_ok=True)
    for suffix,pixels in zip(['albedo','normal','roughness'],f.maps('brick',112)):
        f.png(TEX/('duty_masonry_'+suffix+'.png'),pixels)
    brick=bpy.data.materials.new('Duty red Dutch brick masonry');brick.use_nodes=True
    shader=brick.node_tree.nodes.get('Principled BSDF');shader.inputs['Roughness'].default_value=.88
    for suffix,socket in [('albedo','Base Color'),('normal','Normal'),('roughness','Roughness')]:
        image=bpy.data.images.load(str(TEX/('duty_masonry_'+suffix+'.png')),check_existing=True)
        if suffix!='albedo':image.colorspace_settings.name='Non-Color'
        node=brick.node_tree.nodes.new('ShaderNodeTexImage');node.image=image
        if suffix=='normal':
            normal=brick.node_tree.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.72
            brick.node_tree.links.new(node.outputs['Color'],normal.inputs['Color']);brick.node_tree.links.new(normal.outputs['Normal'],shader.inputs[socket])
        else:brick.node_tree.links.new(node.outputs['Color'],shader.inputs[socket])
    brick['uv_tile_m']=2.1
    m={'brick':brick,
       'concrete':k.material('Duty cast concrete',(.64,.63,.59),.83,0,TEX,'stone'),
       'metal':k.material('Duty zinc roof metal',(.29,.32,.35),.43,.82,TEX,'metal'),
       'paint':k.material('Duty painted powder steel',(.70,.72,.73),.43,.11,TEX,'metal'),
       'dark':k.material('Duty gasket and recessed trim',(.025,.031,.035),.83,0,TEX,'rubber'),
       'glass':k.material('Duty window glass',(.41,.54,.61),.14,.04,alpha=.18)}
    # Authoring preview tint; glTF explicitly exports ACTIVE COLOR0 for all
    # surfaces, matching the validated traffic family approach.
    mat=m['paint'];shader=mat.node_tree.nodes.get('Principled BSDF')
    source=next(link.from_node for link in mat.node_tree.links if link.to_socket==shader.inputs['Base Color'])
    for link in list(mat.node_tree.links):
        if link.to_socket==shader.inputs['Base Color']:mat.node_tree.links.remove(link)
    vertex=mat.node_tree.nodes.new('ShaderNodeVertexColor')
    multiply=mat.node_tree.nodes.new('ShaderNodeMixRGB');multiply.blend_type='MULTIPLY';multiply.inputs[0].default_value=1
    mat.node_tree.links.new(source.outputs['Color'],multiply.inputs[1]);mat.node_tree.links.new(vertex.outputs['Color'],multiply.inputs[2]);mat.node_tree.links.new(multiply.outputs[0],shader.inputs['Base Color'])
    return m


def masonry(root,name,start,end,height,depth,wall_at,windows,m,side=False):
    # Split geometry around real window voids; no dark plane hiding a solid wall.
    cuts=sorted({start,end,*[edge for center,width,_,_ in windows for edge in [center-width/2,center+width/2]]})
    for left,right in zip(cuts,cuts[1:]):
        if right-left<.001:continue
        center=(left+right)/2
        opening=next((value for value in windows if value[0]-value[1]/2<center<value[0]+value[1]/2),None)
        intervals=[(0,height)] if opening is None else [(0,opening[2]-opening[3]/2),(opening[2]+opening[3]/2,height)]
        for low,high in intervals:
            if high<=low:continue
            at=(wall_at,(low+high)/2,center)if side else(center,(low+high)/2,wall_at)
            size=(depth,high-low,right-left)if side else(right-left,high-low,depth)
            B(root,name,at,size,m['brick'])


def window(root,center,height,front,m,side=False,side_sign=1,width=1.85,pane_height=1.93):
    # Wall thickness .4m; the glass sits in an actual inset with deep jambs.
    def at(u,y,d):return (front+d*side_sign,y,u)if side else(u,y,front+d)
    def size(w,h,d):return(d,h,w)if side else(w,h,d)
    for offset in [-width/2,width/2]:
        B(root,'Cast window reveal',at(center+offset,height,.015),size(.09,pane_height+.12,.29),m['concrete'])
        B(root,'Powder window stile',at(center+offset,height,.198),size(.07,pane_height+.04,.08),m['paint'],.005,(.72,.70,.64))
    for offset in [-pane_height/2,pane_height/2]:
        B(root,'Powder window rail',at(center,height+offset,.198),size(width+.06,.066,.08),m['paint'],.005,(.72,.70,.64))
    B(root,'Recessed glazing',at(center,height,.14),size(width-.09,pane_height-.09,.012),m['glass'],0)
    B(root,'Dark glazing gasket',at(center,height,.158),size(.026,pane_height-.09,.026),m['dark'],.002)
    B(root,'Window mullion',at(center,height,.199),size(.045,pane_height-.07,.072),m['paint'],.004,(.72,.70,.64))
    B(root,'Window transom',at(center,height+.38,.199),size(width-.07,.035,.072),m['paint'],.003,(.72,.70,.64))
    B(root,'Projecting window sill',at(center,height-pane_height/2-.062,.10),size(width+.22,.10,.29),m['concrete'])
    B(root,'Masonry window lintel',at(center,height+pane_height/2+.095,.014),size(width+.20,.10,.31),m['concrete'])


def bureau():
    k.clean();m=materials();root=k.empty('BureauShell')
    wall=group(root,'BureauFacade')
    for start,end,centers in [(-9.5,-2.3,[-6.4,-4.2]),(2.3,9.5,[4.2,6.4])]:
        windows=[(x,1.85,2.45,1.93)for x in centers]
        masonry(wall,'Front Dutch brick courses',start,end,4.8,.40,4.5,windows,m)
        for x in centers:window(wall,x,2.45,4.5,m)
    for side in [-1,1]:
        centers=[-2.55,.15,2.6]
        masonry(wall,'Side Dutch brick courses',-4.5,4.5,4.8,.40,side*9.3,[(z,1.7,2.45,1.93)for z in centers],m,True)
        for z in centers:window(wall,z,2.45,side*9.3,m,True,side,1.7)
    # Rear windows are visual gaps; root retains the original solid rear physics.
    B(wall,'Rear masonry',(0,2.4,-4.5),(19,4.8,.40),m['brick'])
    for side in [-1,1]:
        B(wall,'Split concrete front plinth',(side*5.90,.18,4.512),(7.20,.36,.42),m['concrete'])
        B(wall,'Entry casing outside required gap',(side*2.36,1.45,4.504),(.12,2.90,.44),m['concrete'])
    B(wall,'Original clear entrance lintel',(0,3.85,4.5),(4.6,1.9,.38),m['paint'],.013,(.035,.095,.16))
    B(wall,'Shallow entrance cap',(0,2.97,4.5),(4.88,.12,.42),m['metal'],.012)
    # Above the same body top: low hip roof, no new floor/threshold/barrier.
    roof=group(root,'BureauRoof')
    corners=[(-9.70,4.82,-4.72),(9.70,4.82,-4.72),(9.70,4.82,4.72),(-9.70,4.82,4.72)]
    ridge=[(-7.50,6.12,0),(7.50,6.12,0)]
    M(roof,'Zinc hip roof',[*corners,*ridge],[(4,5,1,0),(5,2,1),(5,4,3,2),(4,0,3)],m['metal'])
    B(roof,'Roof underside within original slab',(0,4.81,0),(19.40,.10,9.44),m['dark'],0)
    for front in [-1,1]:
        T(roof,'Continuous rain gutter',[(-9.67,4.79,front*4.70),(9.67,4.79,front*4.70)],.045,m['metal'])
        for x in [-9.21,9.21]:T(wall,'Zinc downpipe',[(x,4.76,front*4.71),(x,.17,front*4.71)],.035,m['metal'])
        for x in [i*.62-7.44 for i in range(25)]:
            T(roof,'Standing roof seam',[(x,4.835,front*4.715),(x,6.135,0)],.008,m['metal'])
    T(roof,'Folded roof ridge',[(-7.55,6.132,0),(7.55,6.132,0)],.024,m['metal'])
    for side in [-1,1]:B(wall,'Side foundation strip',(side*9.31,.18,0),(.42,.36,9.0),m['concrete'])
    for x in [-6.0,6.0]:
        B(roof,'Small original service vent',(x,5.92,-.35),(.46,.29,.58),m['metal'],.018)
        for z in [-.50,-.34,-.18]:B(roof,'Vent cover slots',(x,6.075,z),(.35,.012,.045),m['dark'],.002)
    join(wall,'BureauFacadeSurface');join(roof,'BureauRoofSurface')
    audit(root,'bureau_shell')
    k.finish(root,OUT,'bureau_shell',24,6.2)


def kazerne():
    k.clean();m=materials();root=k.empty('KazerneShell')
    wall=group(root,'KazerneFacade');roof=group(root,'KazerneRoof');equipment=group(root,'GarageMechanisms')
    B(wall,'Rear fire-station masonry',(0,2.8,-5.1),(20,5.6,.40),m['brick'])
    for side in [-1,1]:
        centers=[-3.20,0,2.90]
        masonry(wall,'High side-window masonry',-5.1,5.1,5.6,.40,side*10,[(z,1.8,4.62,1.05)for z in centers],m,True)
        for z in centers:window(wall,z,4.62,side*10,m,True,side,1.8,1.05)
        B(wall,'Side base damp course',(side*10,.18,0),(.42,.36,10.2),m['concrete'])
    B(wall,'Mutually preserved open-bay lintel',(0,4.95,4.9),(20.4,1.3,.40),m['paint'],.015,(.50,.039,.027))
    for x in [-10,-3,4,10]:
        B(wall,'Original bay column',(x,2.15,4.9),(.45,4.30,.45),m['concrete'])
        for z in [4.88,4.98]:B(equipment,'Door guide within column',(x,2.15,z),(.033,4.27,.038),m['metal'],.002)
        B(equipment,'Column impact corner',(x,.48,4.92),(.45,.86,.47),m['paint'],.008,(.33,.34,.28))
    for index,(left,right)in enumerate([(-10,-3),(-3,4),(4,10)]):
        center=(left+right)/2;width=right-left-.45
        B(equipment,'Stored roller cassette',(center,4.61,4.90),(width,.39,.21),m['metal'],.022)
        for y in [4.47,4.55,4.63,4.71,4.79]:B(equipment,'Rolled curtain rib',(center,y,5.017),(width-.12,.025,.015),m['dark'],.003)
        B(equipment,'Side roller drive',(left+.32,4.59,4.82),(.16,.28,.22),m['paint'],.02,(.28,.30,.32))
        T(equipment,'Upper safety cable',[(left+.25,4.48,4.73),(left+.25,5.20,4.73)],.014,m['dark'])
        # Tracks stay wholly above the original4.3m opening.
        T(equipment,'Overhead garage rail',[(left+.30,4.39,4.67),(left+.30,4.65,4.0),(left+.30,4.65,1.6)],.027,m['metal'])
        T(equipment,'Overhead garage rail',[(right-.30,4.39,4.67),(right-.30,4.65,4.0),(right-.30,4.65,1.6)],.027,m['metal'])
    vertices=[(-10.5,5.72,-5.50),(10.5,5.72,-5.50),(10.5,5.72,5.50),(-10.5,5.72,5.50),(-10.5,6.65,0),(10.5,6.65,0)]
    M(roof,'Low Dutch depot zinc roof',vertices,[(4,5,1,0),(5,4,3,2),(3,4,0),(5,2,1)],m['metal'])
    B(roof,'Original garage ceiling plane',(0,5.70,0),(21,.10,11),m['dark'],0)
    for front in [-1,1]:
        T(roof,'Depot gutter',[(-10.44,5.68,front*5.44),(10.44,5.68,front*5.44)],.046,m['metal'])
        for x in [-9.87,9.87]:T(wall,'Depot downpipe',[(x,5.66,front*5.10),(x,.14,front*5.10)],.035,m['metal'])
        for x in [i*.68-9.52 for i in range(29)]:T(roof,'Folded depot roof seam',[(x,5.735,front*5.47),(x,6.662,0)],.009,m['metal'])
    T(roof,'Depot folded ridge',[(-10.5,6.668,0),(10.5,6.668,0)],.026,m['metal'])
    for x in [-7,7]:
        B(roof,'Service extraction curb',(x,6.13,-1.4),(.68,.38,.74),m['metal'],.026)
        B(roof,'Extraction rain cap',(x,6.35,-1.4),(.78,.06,.84),m['metal'],.017)
    join(wall,'KazerneFacadeSurface');join(roof,'KazerneRoofSurface');join(equipment,'GarageMechanismSurface')
    audit(root,'kazerne_shell');k.finish(root,OUT,'kazerne_shell',25,6.7)


def audit(root,asset):
    meshes=[obj for obj in root.children_recursive if obj.type=='MESH']
    triangles=sum(sum(len(p.vertices)-2 for p in obj.data.polygons)for obj in meshes)
    materials={m.name for obj in meshes for m in obj.data.materials}
    assert triangles<=20000,(asset,triangles,'20k budget')
    assert len(materials)<=6,(asset,materials,'six-material budget')
    print('SCENE112_DUTY_BUILDING_BUDGET',asset,triangles,len(materials),flush=True)


def build():
    bureau();kazerne()
    metadata={'units':'metres','up':'+Y','front':'+Z','no_exported_physics':True,
        'bureau':{'root':'BureauShell','world_origin':[0,0,-4.5],'wall_centres_footprint':[19,9],
            'front_z':4.5,'entrance_clear_x':[-2.3,2.3],'entrance_clear_height':2.9,'old_roof_envelope':[19.5,9.5],
            'signs_preserved_world':[[0,4,.24],[0,3.3,.25]],'meshes':['BureauFacadeSurface','BureauRoofSurface']},
        'kazerne':{'root':'KazerneShell','world_origin':[29,0,-6.4],'wall_centres_footprint':[20,10.2],
            'front_z':4.9,'columns_x':[-10,-3,4,10],'column_width':.45,'bay_clear_height':4.3,
            'bay_clear_x':[[-9.775,-3.225],[-2.775,3.775],[4.225,9.775]],'old_roof_envelope':[21,11],
            'signs_preserved_world':[[29,5.05,-1.25]],'meshes':['KazerneFacadeSurface','KazerneRoofSurface','GarageMechanismSurface']}}
    (OUT/'duty_buildings_integration.json').write_text(json.dumps(metadata,indent=2)+'\n')


build()
