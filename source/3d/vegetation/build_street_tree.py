"""Original pruned Noorderkade street tree; packed Blender->GLB, no renders.

Branched bark geometry and individual curved masked leaves. Three materials,
512px authored maps, no external image/model dependency or real-species claim.
"""
from pathlib import Path
import math
import random
import json
import hashlib
import bpy
import numpy as np
from mathutils import Vector,Quaternion

BASE=Path(__file__).resolve().parents[3]
OUT=BASE/'assets/models/vegetation'
TEX=BASE/'assets/textures/vegetation'
SOURCE=BASE/'source/3d/vegetation'
RNG=random.Random(112)
VERT=[];FACES=[];UV=[];MAT=[]


def image(name,values,alpha=None):
    h,w=values.shape[:2]
    data=np.ones((h,w,4),dtype=np.float32)
    data[:,:,:3]=values
    if alpha is not None:data[:,:,3]=alpha
    img=bpy.data.images.new(name,width=w,height=h,alpha=True)
    if not name.endswith('albedo'):img.colorspace_settings.name='Non-Color'
    img.pixels.foreach_set(data.ravel())
    img.filepath_raw=str(TEX/(name+'.png'));img.file_format='PNG';img.save()
    return img


def normal_map(height,amount):
    dy,dx=np.gradient(height)
    normal=np.dstack((-dx*amount,-dy*amount,np.ones_like(height)))
    normal/=np.linalg.norm(normal,axis=2,keepdims=True)
    return normal*.5+.5


def texture_fields():
    n=512;y,x=np.meshgrid(np.arange(n),np.arange(n),indexing='ij')
    rng=np.random.default_rng(112)
    # Vertical bark ridges, irregular crevices and a modest mottled albedo field.
    ridge=np.sin(x*.16+np.sin(y*.017)*.7)+np.sin(x*.47+np.sin(y*.009)*1.6)*.35
    cracks=np.maximum(0,-ridge-.65)
    flecks=rng.random((n,n))-.5
    field=ridge*.28+flecks*.14-cracks*.38
    bark_color=np.clip(np.array([.18,.125,.079])[None,None,:]*(1+field[:,:,None]*.45),0,1)
    bark={'albedo':image('street_bark_albedo',bark_color),
          'normal':image('street_bark_normal',normal_map(field,2.4)),
          'roughness':image('street_bark_roughness',np.repeat(np.clip(.88+field*.06,0,1)[:,:,None],3,2))}
    u=x/(n-1);v=y/(n-1);t=(v-.065)/.87
    center=.5+.028*np.sin(t*math.pi)
    halfwidth=.395*np.maximum(0,np.sin(np.clip(t,0,1)*math.pi))**.78
    halfwidth*=.974+.018*np.sin(t*146)
    mask=((t>=0)&(t<=1)&(np.abs(u-center)<halfwidth)).astype(np.float32)
    mask=np.maximum(mask,((np.abs(u-.5)<.005)&(v>.015)&(v<.12)).astype(np.float32))
    rib=np.exp(-((u-center)/.006)**2)
    veins=np.zeros_like(u)
    for height in [.19,.29,.39,.49,.59,.69,.79]:
        target=height+np.abs(u-center)*.61
        veins=np.maximum(veins,np.exp(-((v-target)/.0045)**2)*(np.abs(u-center)<.32))
    leaf_height=rib*.11+veins*.037+flecks*.008
    leaves=[]
    for name,color in [('leaf_canopy',[.10,.235,.055]),('leaf_sunlit',[.145,.29,.075])]:
        tint=.89+t*.15+flecks*.08+rib*.19+veins*.12
        albedo=np.clip(np.array(color)[None,None,:]*tint[:,:,None],0,1)
        leaves.append({'albedo':image(name+'_albedo',albedo,mask),
                       'normal':image(name+'_normal',normal_map(leaf_height,1.5)),
                       'roughness':image(name+'_roughness',np.repeat(np.clip(.70+flecks*.06,0,1)[:,:,None],3,2))})
    return [bark]+leaves


def material(name,images,masked=False):
    m=bpy.data.materials.new(name);m.use_nodes=True
    shader=m.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Metallic'].default_value=0
    shader.inputs['Roughness'].default_value=.84 if not masked else .70
    for kind,img in images.items():
        node=m.node_tree.nodes.new('ShaderNodeTexImage');node.image=img
        if kind=='albedo':
            m.node_tree.links.new(node.outputs['Color'],shader.inputs['Base Color'])
            if masked:
                clip=m.node_tree.nodes.new('ShaderNodeMath');clip.operation='ROUND'
                m.node_tree.links.new(node.outputs['Alpha'],clip.inputs[0])
                m.node_tree.links.new(clip.outputs[0],shader.inputs['Alpha'])
                m.surface_render_method='DITHERED';m.use_backface_culling=False
        elif kind=='roughness':m.node_tree.links.new(node.outputs['Color'],shader.inputs['Roughness'])
        else:
            normal=m.node_tree.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.75 if not masked else .55
            m.node_tree.links.new(node.outputs['Color'],normal.inputs['Color']);m.node_tree.links.new(normal.outputs['Normal'],shader.inputs['Normal'])
    return m


def add_vertex(v,uv):
    VERT.append(tuple(v));UV.append(uv);return len(VERT)-1


def tube(points,radii,segments=10):
    start=len(VERT)
    for i,(point,radius) in enumerate(zip(points,radii)):
        delta=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(i-1,0)])
        direction=delta.normalized()
        n=direction.cross(Vector((0,1,0))).normalized()
        tangent=direction.cross(n).normalized()
        for j in range(segments):
            angle=j*math.tau/segments
            # Modest uneven bark silhouette; thin branches remain naturally tapered.
            bump=1+.035*math.sin(j*3+i*.61)
            p=Vector(point)+(n*math.cos(angle)+tangent*math.sin(angle))*radius*bump
            add_vertex(p,(j/segments,i*.28))
    for i in range(len(points)-1):
        for j in range(segments):
            FACES.append((start+i*segments+j,start+i*segments+(j+1)%segments,
                          start+(i+1)*segments+(j+1)%segments,start+(i+1)*segments+j));MAT.append(0)
    FACES.append(tuple(start+j for j in range(segments-1,-1,-1)));MAT.append(0)
    FACES.append(tuple(start+(len(points)-1)*segments+j for j in range(segments)));MAT.append(0)


def leaf(at,width,length,normal,roll,mat):
    q=Vector(normal).normalized().to_track_quat('Z','Y')@Quaternion((0,0,1),roll)
    points=[]
    for row in range(3):
        v=row*.5
        for column in range(3):
            u=column*.5
            fold=(1-abs(u-.5)*2)*math.sin(v*math.pi)*.014
            points.append(Vector(at)+q@Vector(((u-.5)*width,(v-.5)*length,fold)))
    lowest=min(p.z for p in points)
    if lowest<3.61:
        for p in points:p.z+=3.61-lowest
    start=len(VERT)
    for i,p in enumerate(points):add_vertex(p,((i%3)*.5,(i//3)*.5))
    for row in range(2):
        for col in range(2):
            i=start+row*3+col
            FACES.append((i,i+1,i+4,i+3));MAT.append(mat)


def build():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    TEX.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True);SOURCE.mkdir(parents=True,exist_ok=True)
    # The two original leaf palettes use separate images; no shader-bake dependency.
    fields=texture_fields()
    mats=[material('Original street bark PBR',fields[0]),material('Original canopy leaves',fields[1],True),material('Original sunlit leaves',fields[2],True)]
    trunk=[(0,0,0),(.008,.006,.16),(.015,.006,.58),(.013,-.004,1.45),(.030,-.025,2.45),(.025,-.018,3.42),(.052,.014,4.30),(.030,.018,5.12),(.082,.031,5.68)]
    tube(trunk,[.198,.206,.188,.158,.133,.104,.074,.046,.016],16)
    leaf_count=0
    for scaffold in range(8):
        angle=scaffold*2.399963+.16
        z=3.39+scaffold*.23
        radial=Vector((math.cos(angle),math.sin(angle),0))
        p0=Vector((.028,-.012,z));p1=p0+radial*.40+Vector((0,0,.27));p2=p0+radial*.91+Vector((0,0,.66));p3=p0+radial*1.46+Vector((0,0,.91))
        tube([p0,p1,p2,p3],[.083,.060,.038,.017],10)
        for branch in range(3):
            side=(branch-1)*.40
            branch_angle=angle+side
            direction=Vector((math.cos(branch_angle),math.sin(branch_angle),0))
            base=p1.lerp(p2,.22+branch*.23)
            tip=base+direction*(.82+.13*(branch%2))+Vector((0,0,.40+.10*branch))
            middle=base.lerp(tip,.52)+Vector((0,0,.065))
            tube([base,middle,tip],[.030,.015,.004],8)
            for fork in [-1,1]:
                twig_start=middle.lerp(tip,.15)
                end=twig_start+Vector((math.cos(branch_angle+fork*.48),math.sin(branch_angle+fork*.48),.38))*.47
                tube([twig_start,twig_start.lerp(end,.48),end],[.010,.005,.0018],6)
            for i in range(62):
                offset=Vector((RNG.gauss(0,.34),RNG.gauss(0,.34),RNG.gauss(0,.25)))
                at=tip+offset
                radius=math.hypot(at.x,at.y)
                if radius>2.0:at.x*=2.0/radius;at.y*=2.0/radius
                at.z=max(3.73,min(6.42,at.z))
                normal=(RNG.uniform(-1,1),RNG.uniform(-1,1),RNG.uniform(-.18,1))
                leaf(at,RNG.uniform(.105,.163),RNG.uniform(.18,.27),normal,RNG.uniform(0,math.tau),2 if RNG.random()<.27 else 1)
                leaf_count+=1
    data=bpy.data.meshes.new('Branched street tree surface');data.from_pydata(VERT,[],FACES);data.update()
    obj=bpy.data.objects.new('StreetTree',data);bpy.context.collection.objects.link(obj)
    for m in mats:data.materials.append(m)
    uv=data.uv_layers.new(name='Original bark and leaf UV0')
    for polygon,index in zip(data.polygons,MAT):
        polygon.material_index=index;polygon.use_smooth=True
        for loop in polygon.loop_indices:uv.data[loop].uv=UV[data.loops[loop].vertex_index]
    uv.active_render=True
    bpy.context.view_layer.objects.active=obj;obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/'street_tree.glb'),export_format='GLB',use_selection=True,
        export_cameras=False,export_lights=False,export_animations=False,export_yup=True)
    for img in bpy.data.images:
        if img.filepath:
            img.pack();img.filepath=bpy.path.relpath(img.filepath,start=str(SOURCE))
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'street_tree.blend'))
    triangles=sum(len(p.vertices)-2 for p in data.polygons)
    minimum=min(VERT[i][2] for face,mat in zip(FACES,MAT) if mat>0 for i in face)
    stats={'asset':'street_tree','author':'SCENE112 original procedural Blender authoring','license':'Private/proprietary project content; docs/LICENSES.md',
        'blender':bpy.app.version_string,'materials':3,'triangles':triangles,'leaves':leaf_count,'canopy_min_height_m':minimum,
        'overall_height_m':max(v[2] for v in VERT),'canopy_radius_m':max(math.hypot(v[0],v[1]) for v in VERT),
        'physical_trunk_radius_m':.20,'source_builder':'source/3d/vegetation/build_street_tree.py','source_blend':'source/3d/vegetation/street_tree.blend',
        'runtime_glb':'assets/models/vegetation/street_tree.glb','texture_directory':'assets/textures/vegetation','packed_images':True,
        'glb_sha256':hashlib.sha256((OUT/'street_tree.glb').read_bytes()).hexdigest(),'renders':0}
    (OUT/'street_tree_manifest.json').write_text(json.dumps(stats,indent=2))
    assert triangles<=20000 and minimum>=3.6,stats
    print('SCENE112_STREET_TREE_BUILT',json.dumps(stats),flush=True)


build()
