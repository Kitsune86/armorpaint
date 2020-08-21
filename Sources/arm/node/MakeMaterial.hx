package arm.node;

import iron.data.SceneFormat;
import iron.data.ShaderData;
import iron.data.MaterialData;
import arm.ui.UIHeader;
import arm.ui.UINodes;
import arm.ui.UISidebar;
import arm.shader.NodeShader;
import arm.shader.NodeShaderContext;
import arm.shader.NodeShaderData;
import arm.shader.ShaderFunctions;
import arm.Enums;

class MakeMaterial {

	public static var defaultScon: ShaderContext = null;
	public static var defaultMcon: MaterialContext = null;

	public static var heightUsed = false;
	public static var emisUsed = false;
	public static var subsUsed = false;

	static function getMOut(): Bool {
		for (n in UINodes.inst.getCanvasMaterial().nodes) if (n.type == "OUTPUT_MATERIAL_PBR") return true;
		return false;
	}

	public static function parseMeshMaterial() {
		if (UIHeader.inst.worktab.position == SpaceRender) return;
		var m = Project.materials[0].data;
		var scon: ShaderContext = null;
		for (c in m.shader.contexts) if (c.raw.name == "mesh") { scon = c; break; }
		if (scon != null) {
			m.shader.raw.contexts.remove(scon.raw);
			m.shader.contexts.remove(scon);
		}
		var con = make_mesh(new NodeShaderData({name: "Material", canvas: null}));
		if (scon != null) scon.delete();
		scon = new ShaderContext(con.data, function(scon: ShaderContext){});
		scon.overrideContext = {}
		if (con.frag.sharedSamplers.length > 0) {
			var sampler = con.frag.sharedSamplers[0];
			scon.overrideContext.shared_sampler = sampler.substr(sampler.lastIndexOf(" ") + 1);
		}
		if (!Context.textureFilter) {
			scon.overrideContext.filter = "point";
		}
		m.shader.raw.contexts.push(scon.raw);
		m.shader.contexts.push(scon);
		Context.ddirty = 2;

		makeVoxel(m);
	}

	public static function parseParticleMaterial() {
		var m = Context.particleMaterial;
		var sc: ShaderContext = null;
		for (c in m.shader.contexts) if (c.raw.name == "mesh") { sc = c; break; }
		if (sc != null) {
			m.shader.raw.contexts.remove(sc.raw);
			m.shader.contexts.remove(sc);
		}
		var con = make_particle(new NodeShaderData({name: "MaterialParticle", canvas: null}));
		if (sc != null) sc.delete();
		sc = new ShaderContext(con.data, function(sc: ShaderContext){});
		m.shader.raw.contexts.push(sc.raw);
		m.shader.contexts.push(sc);
	}

	public static function parseMeshPreviewMaterial() {
		if (!getMOut()) return;

		var m = UIHeader.inst.worktab.position == SpaceRender ? Context.materialScene.data : Project.materials[0].data;
		var scon: ShaderContext = null;
		for (c in m.shader.contexts) if (c.raw.name == "mesh") { scon = c; break; }
		m.shader.raw.contexts.remove(scon.raw);
		m.shader.contexts.remove(scon);

		var mcon: TMaterialContext = { name: "mesh", bind_textures: [] };

		var sd = new NodeShaderData({name: "Material", canvas: null});
		var con = make_mesh_preview(sd, mcon);

		for (i in 0...m.contexts.length) {
			if (m.contexts[i].raw.name == "mesh") {
				m.contexts[i] = new MaterialContext(mcon, function(self: MaterialContext) {});
				break;
			}
		}

		if (scon != null) scon.delete();

		var compileError = false;
		scon = new ShaderContext(con.data, function(scon: ShaderContext) {
			if (scon == null) compileError = true;
		});
		if (compileError) return;

		m.shader.raw.contexts.push(scon.raw);
		m.shader.contexts.push(scon);

		if (UIHeader.inst.worktab.position == SpaceRender) {
			makeVoxel(m);
		}
	}

	static function makeVoxel(m: MaterialData) {
		#if rp_voxelao
		var rebuild = heightUsed;
		#if arm_world
		rebuild = true;
		#end
		if (Config.raw.rp_gi != false && rebuild) {
			var scon: ShaderContext = null;
			for (c in m.shader.contexts) if (c.raw.name == "voxel") { scon = c; break; }
			if (scon != null) make_voxel(scon);
		}
		#end
	}

	public static function parsePaintMaterial() {
		if (!getMOut()) return;

		if (UIHeader.inst.worktab.position == SpaceRender) {
			parseMeshPreviewMaterial();
			return;
		}

		var m = Project.materials[0].data;
		var scon: ShaderContext = null;
		var mcon: MaterialContext = null;
		for (c in m.shader.contexts) {
			if (c.raw.name == "paint") {
				m.shader.raw.contexts.remove(c.raw);
				m.shader.contexts.remove(c);
				if (c != defaultScon) c.delete();
				break;
			}
		}
		for (c in m.contexts) {
			if (c.raw.name == "paint") {
				m.raw.contexts.remove(c.raw);
				m.contexts.remove(c);
				break;
			}
		}

		var sdata = new NodeShaderData({ name: "Material", canvas: UINodes.inst.getCanvasMaterial() });
		var mcon = { name: "paint", bind_textures: [] };
		var con = make_paint(sdata, mcon);

		var compileError = false;
		var scon = new ShaderContext(con.data, function(scon: ShaderContext) {
			if (scon == null) compileError = true;
		});
		if (compileError) return;
		scon.overrideContext = {}
		scon.overrideContext.addressing = "repeat";
		var mcon = new MaterialContext(mcon, function(mcon: MaterialContext) {});

		m.shader.raw.contexts.push(scon.raw);
		m.shader.contexts.push(scon);
		m.raw.contexts.push(mcon.raw);
		m.contexts.push(mcon);

		if (defaultScon == null) defaultScon = scon;
		if (defaultMcon == null) defaultMcon = mcon;
	}

	public static function parseBrush() {
		Brush.parse(Context.brush.canvas, false);
	}

	public static inline function make_paint(data: NodeShaderData, matcon: TMaterialContext): NodeShaderContext {
		return MakePaint.run(data, matcon);
	}

	public static inline function make_mesh(data: NodeShaderData): NodeShaderContext {
		return MakeMesh.run(data);
	}

	public static inline function make_mesh_preview(data: NodeShaderData, matcon: TMaterialContext): NodeShaderContext {
		return MakeMeshPreview.run(data, matcon);
	}

	public static inline function make_voxel(data: iron.data.ShaderData.ShaderContext) {
		#if rp_voxelao
		MakeVoxel.run(data);
		#end
	}

	public static inline function make_particle(data: NodeShaderData): NodeShaderContext {
		return MakeParticle.run(data);
	}

	public static function blendMode(frag: NodeShader, blending: Int, cola: String, colb: String, opac: String): String {
		if (blending == BlendMix) {
			return 'mix($cola, $colb, $opac)';
		}
		else if (blending == BlendDarken) {
			return 'mix($cola, min($cola, $colb), $opac)';
		}
		else if (blending == BlendMultiply) {
			return 'mix($cola, $cola * $colb, $opac)';
		}
		else if (blending == BlendBurn) {
			return 'mix($cola, vec3(1.0, 1.0, 1.0) - (vec3(1.0, 1.0, 1.0) - $cola) / $colb, $opac)';
		}
		else if (blending == BlendLighten) {
			return 'max($cola, $colb * $opac)';
		}
		else if (blending == BlendScreen) {
			return '(vec3(1.0, 1.0, 1.0) - (vec3(1.0 - $opac, 1.0 - $opac, 1.0 - $opac) + $opac * (vec3(1.0, 1.0, 1.0) - $colb)) * (vec3(1.0, 1.0, 1.0) - $cola))';
		}
		else if (blending == BlendDodge) {
			return 'mix($cola, $cola / (vec3(1.0, 1.0, 1.0) - $colb), $opac)';
		}
		else if (blending == BlendAdd) {
			return 'mix($cola, $cola + $colb, $opac)';
		}
		else if (blending == BlendOverlay) {
			#if (kha_direct3d11 || kha_direct3d12 || kha_metal)
			return 'mix($cola, ($cola < vec3(0.5, 0.5, 0.5) ? vec3(2.0, 2.0, 2.0) * $cola * $colb : vec3(1.0, 1.0, 1.0) - vec3(2.0, 2.0, 2.0) * (vec3(1.0, 1.0, 1.0) - $colb) * (vec3(1.0, 1.0, 1.0) - $cola)), $opac)';
			#else
			return 'mix($cola, $colb, $opac)'; // TODO
			#end
		}
		else if (blending == BlendSoftLight) {
			return '((1.0 - $opac) * $cola + $opac * ((vec3(1.0, 1.0, 1.0) - $cola) * $colb * $cola + $cola * (vec3(1.0, 1.0, 1.0) - (vec3(1.0, 1.0, 1.0) - $colb) * (vec3(1.0, 1.0, 1.0) - $cola))))';
		}
		else if (blending == BlendLinearLight) {
			return '($cola + $opac * (vec3(2.0, 2.0, 2.0) * ($colb - vec3(0.5, 0.5, 0.5))))';
		}
		else if (blending == BlendDifference) {
			return 'mix($cola, abs($cola - $colb), $opac)';
		}
		else if (blending == BlendSubtract) {
			return 'mix($cola, $cola - $colb, $opac)';
		}
		else if (blending == BlendDivide) {
			return 'vec3(1.0 - $opac, 1.0 - $opac, 1.0 - $opac) * $cola + vec3($opac, $opac, $opac) * $cola / $colb';
		}
		else if (blending == BlendHue) {
			frag.add_function(ShaderFunctions.str_hue_sat);
			return 'mix($cola, hsv_to_rgb(vec3(rgb_to_hsv($colb).r, rgb_to_hsv($cola).g, rgb_to_hsv($cola).b)), $opac)';
		}
		else if (blending == BlendSaturation) {
			frag.add_function(ShaderFunctions.str_hue_sat);
			return 'mix($cola, hsv_to_rgb(vec3(rgb_to_hsv($cola).r, rgb_to_hsv($colb).g, rgb_to_hsv($cola).b)), $opac)';
		}
		else if (blending == BlendColor) {
			frag.add_function(ShaderFunctions.str_hue_sat);
			return 'mix($cola, hsv_to_rgb(vec3(rgb_to_hsv($colb).r, rgb_to_hsv($colb).g, rgb_to_hsv($cola).b)), $opac)';
		}
		else { // BlendValue
			frag.add_function(ShaderFunctions.str_hue_sat);
			return 'mix($cola, hsv_to_rgb(vec3(rgb_to_hsv($cola).r, rgb_to_hsv($cola).g, rgb_to_hsv($colb).b)), $opac)';
		}
	}

	public static inline function getDisplaceStrength():Float {
		var sc = Context.mainObject().transform.scale.x;
		return Config.raw.displace_strength * 0.02 * sc;
	}

	public static inline function voxelgiHalfExtents():String {
		var ext = Context.vxaoExt;
		return 'const vec3 voxelgiHalfExtents = vec3($ext, $ext, $ext);';
	}
}