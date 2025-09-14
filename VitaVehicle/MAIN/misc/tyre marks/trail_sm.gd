extends Node3D

@export var width_scale := 0.35

var last_pos := transform
var g := Vector3(0,0,0)

var vertices := []

var del := 0

var wid := 0.125

var inserting := false
var inserting2 := false

var current_trail_node: MeshInstance3D = null
var current_trail: ImmediateMesh = null
var drawers := []


# i spent 5 days trying to figure out why the skids were not working properly
# the immediate mesh resource was shared between all the skids :/


func add_segment():
	var ppos = global_transform
	
	vertices.append( [
		
		ppos.origin + (ppos.basis.orthonormalized() * Vector3(wid,0,0)),
		ppos.origin - (ppos.basis.orthonormalized() * Vector3(wid,0,0)),
		
		ppos.origin,
		] )
	
	last_pos = ppos


#region internal
func _ready() -> void:
	wid = Convert.mm_to_meter(Helper.get_ancestor(self, 2).TyreSettings["Width (mm)"]) * Constants.METER_TO_UNIT * width_scale

func _physics_process(_delta):
	#get_parent().get_node("Camera").rotation_degrees.y += 20
	
	del -= 1
	
	for i in drawers:
		i.delete_wait -= 1
		if i.delete_wait<0:
			if current_trail == i:
				current_trail = null
			i.queue_free()
			drawers.remove_at(0)
		
	if del<0 and inserting:
		del = 5
		add_segment()

func _process(_delta):
	
	inserting = Helper.get_ancestor(self, 2).slip_perc.length() > Helper.get_ancestor(self, 2).stress +20.0 and Helper.get_ancestor(self, 2).is_colliding()
	
	position.y = -Helper.get_ancestor(self, 2).w_size + Constants.SKIDMARK_HEIGHT
	
	if inserting2 != inserting:
		inserting2 = inserting
		if inserting2:
			
			if not current_trail_node == null:
				var t = current_trail_node.global_transform
				remove_child(current_trail_node)
				get_tree().get_current_scene().add_child(current_trail_node)
				current_trail_node.global_transform = t
			
			vertices.clear()
			current_trail_node = $trail.duplicate()
			# we changed our node so we need to update our resource too.
			# not sure if i should use new resource or use a copy of the old one
			# but im not noticing any difference by using a new one, soo...
			current_trail_node.mesh = ImmediateMesh.new()
			current_trail = current_trail_node.mesh
			
			add_child(current_trail_node)
			drawers.append(current_trail_node)
	
	if (global_transform.origin - g).length_squared()>0.01:
		look_at(g,Vector3(0,1,0)) # WARNING BUG: Colinear vectors. BAD: When falling down, node and target are in the same position because of Y being up. This causes a failure error.
	
	g = global_transform.origin
	var ppos = global_transform
	
	if not current_trail_node == null:
		if inserting:
			current_trail_node.delete_wait = 180
			if len(vertices)>0:
				vertices[len(vertices)-1][0] = ((ppos.origin + ppos.basis.orthonormalized() * Vector3(wid,0,0)))
				vertices[len(vertices)-1][1] = ((ppos.origin - ppos.basis.orthonormalized() * Vector3(wid,0,0)))
				vertices[len(vertices)-1][2] = ppos.origin
			
		current_trail_node.global_transform.basis = get_tree().get_current_scene().global_transform.basis
		current_trail.clear_surfaces()
		
		if vertices.size() > 0 : # check if we actually got stuff to make
			current_trail.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			for i in vertices:
				if len(i)>0:
					# with the vulkan renderer (forward+ and mobile) you will get the following error
					## "draw_list_draw: Too few vertices (2) for the render primitive set in the render pipeline (3)."
					
					current_trail.surface_add_vertex(i[0] -global_transform.origin)
					current_trail.surface_add_vertex(i[1] -global_transform.origin)
			
			current_trail.surface_end()
#endregion internal
