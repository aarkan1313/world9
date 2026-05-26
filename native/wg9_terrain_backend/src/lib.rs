use godot::classes::{IRefCounted, RefCounted};
use godot::prelude::*;

const BACKEND_SCHEMA: &str = "worldgen9.native_backend.v1";
const BACKEND_CLASS_NAME: &str = "Wg9TerrainNativeBackend";
const MAX_NATIVE_GRID_VERTICES: usize = 1_048_576;

struct Wg9TerrainBackendExtension;

#[gdextension]
unsafe impl ExtensionLibrary for Wg9TerrainBackendExtension {}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct Wg9TerrainNativeBackend {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for Wg9TerrainNativeBackend {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl Wg9TerrainNativeBackend {
    #[func]
    pub fn backend_name(&self) -> GString {
        BACKEND_CLASS_NAME.into()
    }

    #[func]
    pub fn debug_status(&self) -> VarDictionary {
        let mut status = VarDictionary::new();
        status.set("schema", BACKEND_SCHEMA);
        status.set("backend_class", BACKEND_CLASS_NAME);
        status.set("language", "rust");
        status.set("godot_api", "4.6");
        status.set("status", "registered");
        status.set("supports_height_grid_generation", true);
        status.set("supports_mesh_payload_generation", true);
        status.set("supports_clipmap_mesh_payload_generation", true);
        status.set("supports_surface_detail_generation", true);
        status.set("supports_threaded_calls", true);
        status.set("supports_gpu_generation", false);
        status.set(
            "next_step",
            "move native chunk payload builds onto a worker queue, then validate skirted LOD rings before far clipmaps/GPU detail tiers",
        );
        status
    }

    #[func]
    pub fn chunk_grid_metrics(&self, request: VarDictionary) -> VarDictionary {
        let vertices_per_side = request_i64(&request, "vertices_per_side", 129).max(2);
        let chunk_size_m = request_f64(&request, "chunk_size_m", 2048.0).max(1.0);
        let vertex_count = vertices_per_side * vertices_per_side;
        let quad_count = (vertices_per_side - 1) * (vertices_per_side - 1);
        let triangle_count = quad_count * 2;
        let index_count = triangle_count * 3;
        let spacing_m = chunk_size_m / ((vertices_per_side - 1) as f64);

        let mut metrics = VarDictionary::new();
        metrics.set("schema", BACKEND_SCHEMA);
        metrics.set("backend_class", BACKEND_CLASS_NAME);
        metrics.set("vertices_per_side", vertices_per_side);
        metrics.set("chunk_size_m", chunk_size_m);
        metrics.set("sample_spacing_m", spacing_m);
        metrics.set("vertex_count", vertex_count);
        metrics.set("quad_count", quad_count);
        metrics.set("triangle_count", triangle_count);
        metrics.set("index_count", index_count);
        metrics.set("position_normal_uv_bytes", vertex_count * 32);
        metrics.set("index_bytes", index_count * 4);
        metrics.set("cpu_height_bytes", vertex_count * 4);
        metrics
    }

    #[func]
    pub fn build_mesh_payload_from_height(
        &self,
        height: PackedFloat32Array,
        vertices_per_side: i64,
        step_m: f64,
    ) -> VarDictionary {
        let count = match validated_grid_count(vertices_per_side) {
            Ok(value) => value,
            Err(error) => return fail_dictionary(error),
        };
        if !step_m.is_finite() || step_m <= 0.0 {
            return fail_dictionary(format!("invalid_step_m:{step_m}"));
        }
        let expected = count * count;
        let height_values = height.as_slice();
        if let Some(error) = validate_height_values(height_values, expected) {
            return fail_dictionary(error);
        }
        let step = step_m as f32;
        let vertices = build_vertices(height_values, count, step);
        let normals = build_normals(height_values, count, step);
        let uvs = build_uvs(count);
        let indices = build_indices(count);

        let mut payload = VarDictionary::new();
        payload.set("schema", BACKEND_SCHEMA);
        payload.set("backend_class", BACKEND_CLASS_NAME);
        payload.set("status", "pass");
        payload.set("vertices_per_side", vertices_per_side);
        payload.set("step_m", step_m);
        payload.set("vertices", &vertices);
        payload.set("normals", &normals);
        payload.set("uvs", &uvs);
        payload.set("indices", &indices);
        payload
    }

    #[func]
    pub fn build_clipmap_mesh_payload_from_height(
        &self,
        height: PackedFloat32Array,
        vertices_per_side: i64,
        step_m: f64,
        outer_extent_m: f64,
        inner_extent_m: f64,
    ) -> VarDictionary {
        let count = match validated_grid_count(vertices_per_side) {
            Ok(value) => value,
            Err(error) => return fail_dictionary(error),
        };
        if !step_m.is_finite() || step_m <= 0.0 {
            return fail_dictionary(format!("invalid_step_m:{step_m}"));
        }
        if !outer_extent_m.is_finite() || outer_extent_m <= 0.0 {
            return fail_dictionary(format!("invalid_outer_extent_m:{outer_extent_m}"));
        }
        if !inner_extent_m.is_finite() || inner_extent_m < 0.0 || inner_extent_m >= outer_extent_m {
            return fail_dictionary(format!("invalid_inner_extent_m:{inner_extent_m}"));
        }
        let expected = count * count;
        let height_values = height.as_slice();
        if let Some(error) = validate_height_values(height_values, expected) {
            return fail_dictionary(error);
        }
        let step = step_m as f32;
        let outer_extent = outer_extent_m as f32;
        let inner_extent = inner_extent_m as f32;
        let vertices = build_centered_vertices(height_values, count, step, outer_extent);
        let normals = build_normals(height_values, count, step);
        let uvs = build_uvs(count);
        let indices = build_clipmap_indices(count, step, outer_extent, inner_extent);

        let mut payload = VarDictionary::new();
        payload.set("schema", BACKEND_SCHEMA);
        payload.set("backend_class", BACKEND_CLASS_NAME);
        payload.set("status", "pass");
        payload.set("vertices_per_side", vertices_per_side);
        payload.set("step_m", step_m);
        payload.set("outer_extent_m", outer_extent_m);
        payload.set("inner_extent_m", inner_extent_m);
        payload.set("vertices", &vertices);
        payload.set("normals", &normals);
        payload.set("uvs", &uvs);
        payload.set("indices", &indices);
        payload
    }

    #[func]
    pub fn build_visual_displacement_from_height(
        &self,
        height: PackedFloat32Array,
        vertices_per_side: i64,
        edge_lock_samples: i64,
    ) -> VarDictionary {
        let count = vertices_per_side.max(2) as usize;
        let expected = count * count;
        if height.len() != expected {
            return fail_dictionary(format!(
                "height_size:{} expected:{}",
                height.len(),
                expected
            ));
        }
        let edge_lock = edge_lock_samples.max(1) as usize;
        let (values, max_abs_m) = build_visual_displacement(height.as_slice(), count, edge_lock);

        let mut payload = VarDictionary::new();
        payload.set("schema", BACKEND_SCHEMA);
        payload.set("backend_class", BACKEND_CLASS_NAME);
        payload.set("status", "pass");
        payload.set("vertices_per_side", vertices_per_side);
        payload.set("edge_lock_samples", edge_lock as i64);
        payload.set("values", &PackedFloat32Array::from(values));
        payload.set("max_abs_m", max_abs_m);
        payload
    }

    #[func]
    #[allow(clippy::too_many_arguments)]
    pub fn sample_height_grid_prepared(
        &self,
        origin_x: f64,
        origin_z: f64,
        step_m: f64,
        count_x: i64,
        count_z: i64,
        world_seed: i64,
        region_size_m: f64,
        base_rx: i64,
        base_rz: i64,
        corner_entries: AnyArray,
    ) -> VarDictionary {
        let count_x = count_x.max(1) as usize;
        let count_z = count_z.max(1) as usize;
        if !origin_x.is_finite()
            || !origin_z.is_finite()
            || !step_m.is_finite()
            || !region_size_m.is_finite()
            || step_m <= 0.0
            || region_size_m <= 0.0
        {
            return fail_dictionary(format!(
                "invalid_grid_request origin_x:{origin_x} origin_z:{origin_z} step_m:{step_m} region_size_m:{region_size_m}"
            ));
        }
        let corners = match parse_corners(&corner_entries) {
            Ok(value) => value,
            Err(error) => return fail_dictionary(error),
        };
        if corners.len() != 4 {
            return fail_dictionary(format!("corner_count:{} expected:4", corners.len()));
        }
        let values = sample_prepared_height_grid(
            origin_x,
            origin_z,
            step_m,
            count_x,
            count_z,
            world_seed,
            region_size_m,
            base_rx,
            base_rz,
            &corners,
        );
        let mut payload = VarDictionary::new();
        payload.set("schema", BACKEND_SCHEMA);
        payload.set("backend_class", BACKEND_CLASS_NAME);
        payload.set("status", "pass");
        payload.set("count_x", count_x as i64);
        payload.set("count_z", count_z as i64);
        payload.set("values", &PackedFloat32Array::from(values));
        payload
    }

    #[func]
    #[allow(clippy::too_many_arguments)]
    pub fn build_chunk_payload_prepared(
        &self,
        origin_x: f64,
        origin_z: f64,
        step_m: f64,
        vertices_per_side: i64,
        world_seed: i64,
        region_size_m: f64,
        base_rx: i64,
        base_rz: i64,
        corner_entries: AnyArray,
    ) -> VarDictionary {
        let count = vertices_per_side.max(2) as usize;
        if !origin_x.is_finite()
            || !origin_z.is_finite()
            || !step_m.is_finite()
            || !region_size_m.is_finite()
            || step_m <= 0.0
            || region_size_m <= 0.0
        {
            return fail_dictionary(format!(
                "invalid_chunk_request origin_x:{origin_x} origin_z:{origin_z} step_m:{step_m} region_size_m:{region_size_m}"
            ));
        }
        let corners = match parse_corners(&corner_entries) {
            Ok(value) => value,
            Err(error) => return fail_dictionary(error),
        };
        if corners.len() != 4 {
            return fail_dictionary(format!("corner_count:{} expected:4", corners.len()));
        }
        let height_values = sample_prepared_height_grid(
            origin_x,
            origin_z,
            step_m,
            count,
            count,
            world_seed,
            region_size_m,
            base_rx,
            base_rz,
            &corners,
        );
        let step = step_m as f32;
        let vertices = build_vertices(&height_values, count, step);
        let normals = build_normals(&height_values, count, step);
        let uvs = build_uvs(count);
        let indices = build_indices(count);

        let mut payload = VarDictionary::new();
        payload.set("schema", BACKEND_SCHEMA);
        payload.set("backend_class", BACKEND_CLASS_NAME);
        payload.set("status", "pass");
        payload.set("vertices_per_side", vertices_per_side);
        payload.set("step_m", step_m);
        payload.set("height", &PackedFloat32Array::from(height_values));
        payload.set("vertices", &vertices);
        payload.set("normals", &normals);
        payload.set("uvs", &uvs);
        payload.set("indices", &indices);
        payload
    }
}

fn request_i64(request: &VarDictionary, key: &str, fallback: i64) -> i64 {
    request
        .get(key)
        .map(|value| value.to::<i64>())
        .unwrap_or(fallback)
}

fn request_f64(request: &VarDictionary, key: &str, fallback: f64) -> f64 {
    request
        .get(key)
        .map(|value| value.to::<f64>())
        .unwrap_or(fallback)
}

fn fail_dictionary(error: String) -> VarDictionary {
    let mut payload = VarDictionary::new();
    payload.set("schema", BACKEND_SCHEMA);
    payload.set("backend_class", BACKEND_CLASS_NAME);
    payload.set("status", "fail");
    payload.set("error", error.as_str());
    payload
}

fn validated_grid_count(vertices_per_side: i64) -> Result<usize, String> {
    if vertices_per_side < 2 {
        return Err(format!("invalid_vertices_per_side:{vertices_per_side}"));
    }
    let count = vertices_per_side as usize;
    match count.checked_mul(count) {
        Some(total) if total <= MAX_NATIVE_GRID_VERTICES => Ok(count),
        Some(total) => Err(format!(
            "grid_vertex_count_exceeded:{total} max:{MAX_NATIVE_GRID_VERTICES}"
        )),
        None => Err(format!("grid_vertex_count_overflow:{vertices_per_side}")),
    }
}

fn validate_height_values(values: &[f32], expected: usize) -> Option<String> {
    if values.len() != expected {
        return Some(format!(
            "height_size:{} expected:{}",
            values.len(),
            expected
        ));
    }
    for (index, value) in values.iter().enumerate() {
        if !value.is_finite() {
            return Some(format!("height_non_finite:index:{index} value:{value}"));
        }
    }
    None
}

#[allow(clippy::too_many_arguments)]
fn sample_prepared_height_grid(
    origin_x: f64,
    origin_z: f64,
    step_m: f64,
    count_x: usize,
    count_z: usize,
    world_seed: i64,
    region_size_m: f64,
    base_rx: i64,
    base_rz: i64,
    corners: &[PreparedCorner],
) -> Vec<f32> {
    let mut values = Vec::with_capacity(count_x * count_z);
    for z_index in 0..count_z {
        let z = origin_z + (z_index as f64) * step_m;
        let gz = z / region_size_m;
        let tz = smoothstep_unit(gz - base_rz as f64);
        let wz0 = 1.0 - tz;
        let wz1 = tz;
        for x_index in 0..count_x {
            let x = origin_x + (x_index as f64) * step_m;
            let gx = x / region_size_m;
            let tx = smoothstep_unit(gx - base_rx as f64);
            let wx0 = 1.0 - tx;
            let weights = [wx0 * wz0, tx * wz0, wx0 * wz1, tx * wz1];
            values.push(sample_height_with_corners(
                x,
                z,
                world_seed,
                region_size_m,
                corners,
                &weights,
            ));
        }
    }
    values
}

fn build_vertices(height: &[f32], count: usize, step_m: f32) -> PackedVector3Array {
    let mut vertices = Vec::with_capacity(count * count);
    for z in 0..count {
        for x in 0..count {
            let index = z * count + x;
            vertices.push(Vector3::new(
                x as f32 * step_m,
                height[index],
                z as f32 * step_m,
            ));
        }
    }
    PackedVector3Array::from(vertices)
}

fn build_centered_vertices(
    height: &[f32],
    count: usize,
    step_m: f32,
    outer_extent_m: f32,
) -> PackedVector3Array {
    let mut vertices = Vec::with_capacity(count * count);
    for z in 0..count {
        let local_z = -outer_extent_m + z as f32 * step_m;
        for x in 0..count {
            let index = z * count + x;
            let local_x = -outer_extent_m + x as f32 * step_m;
            vertices.push(Vector3::new(local_x, height[index], local_z));
        }
    }
    PackedVector3Array::from(vertices)
}

fn build_normals(height: &[f32], count: usize, step_m: f32) -> PackedVector3Array {
    let mut normals = Vec::with_capacity(count * count);
    for z in 0..count {
        for x in 0..count {
            let dx = gradient_x(height, count, x, z, step_m);
            let dz = gradient_z(height, count, x, z, step_m);
            normals.push(Vector3::new(-dx, 1.0, -dz).normalized());
        }
    }
    PackedVector3Array::from(normals)
}

fn build_visual_displacement(height: &[f32], count: usize, edge_lock: usize) -> (Vec<f32>, f32) {
    let mut displacement = Vec::with_capacity(count * count);
    let mut max_abs_m = 0.0_f32;
    for z in 0..count {
        for x in 0..count {
            let center = height_at_clamped(height, count, x as isize, z as isize);
            let mut total = 0.0_f32;
            for dz in -1..=1 {
                for dx in -1..=1 {
                    total += height_at_clamped(height, count, x as isize + dx, z as isize + dz);
                }
            }
            let residual = center - total / 9.0;
            let distance_to_edge = x.min(z).min(count - 1 - x).min(count - 1 - z);
            let edge_fade = ((distance_to_edge as f32) / (edge_lock as f32)).clamp(0.0, 1.0);
            let value = residual * edge_fade;
            max_abs_m = max_abs_m.max(value.abs());
            displacement.push(value);
        }
    }
    (displacement, max_abs_m)
}

fn height_at_clamped(height: &[f32], count: usize, x: isize, z: isize) -> f32 {
    let clamped_x = x.clamp(0, (count - 1) as isize) as usize;
    let clamped_z = z.clamp(0, (count - 1) as isize) as usize;
    height[clamped_z * count + clamped_x]
}

fn build_uvs(count: usize) -> PackedVector2Array {
    let mut uvs = Vec::with_capacity(count * count);
    let denom = (count - 1) as f32;
    for z in 0..count {
        for x in 0..count {
            uvs.push(Vector2::new(x as f32 / denom, z as f32 / denom));
        }
    }
    PackedVector2Array::from(uvs)
}

fn build_indices(count: usize) -> PackedInt32Array {
    let quads = count - 1;
    let mut indices = Vec::with_capacity(quads * quads * 6);
    for z in 0..quads {
        let row = z * count;
        let next_row = (z + 1) * count;
        for x in 0..quads {
            let a = (row + x) as i32;
            let b = (row + x + 1) as i32;
            let c = (next_row + x) as i32;
            let d = (next_row + x + 1) as i32;
            indices.push(a);
            indices.push(c);
            indices.push(b);
            indices.push(b);
            indices.push(c);
            indices.push(d);
        }
    }
    PackedInt32Array::from(indices)
}

fn build_clipmap_indices(
    count: usize,
    step_m: f32,
    outer_extent_m: f32,
    inner_extent_m: f32,
) -> PackedInt32Array {
    let quads = count - 1;
    let mut indices = Vec::with_capacity(quads * quads * 6);
    for z in 0..quads {
        let z_center = -outer_extent_m + (z as f32 + 0.5) * step_m;
        let row = z * count;
        let next_row = (z + 1) * count;
        for x in 0..quads {
            let x_center = -outer_extent_m + (x as f32 + 0.5) * step_m;
            if x_center.abs() < inner_extent_m && z_center.abs() < inner_extent_m {
                continue;
            }
            let a = (row + x) as i32;
            let b = (row + x + 1) as i32;
            let c = (next_row + x) as i32;
            let d = (next_row + x + 1) as i32;
            indices.push(a);
            indices.push(c);
            indices.push(b);
            indices.push(b);
            indices.push(c);
            indices.push(d);
        }
    }
    PackedInt32Array::from(indices)
}

fn gradient_x(height: &[f32], count: usize, x: usize, z: usize, step_m: f32) -> f32 {
    let row = z * count;
    if x == 0 {
        return (height[row + 1] - height[row]) / step_m;
    }
    if x == count - 1 {
        return (height[row + x] - height[row + x - 1]) / step_m;
    }
    (height[row + x + 1] - height[row + x - 1]) / (step_m * 2.0)
}

fn gradient_z(height: &[f32], count: usize, x: usize, z: usize, step_m: f32) -> f32 {
    if z == 0 {
        return (height[count + x] - height[x]) / step_m;
    }
    if z == count - 1 {
        let row = z * count;
        let prev_row = (z - 1) * count;
        return (height[row + x] - height[prev_row + x]) / step_m;
    }
    (height[(z + 1) * count + x] - height[(z - 1) * count + x]) / (step_m * 2.0)
}

#[derive(Clone)]
struct PreparedCorner {
    entries: Vec<PreparedEntry>,
}

#[derive(Clone)]
struct PreparedEntry {
    family: String,
    bias: f64,
    runtime_weight: f64,
    moderation: f64,
    relief_scale_m: f64,
    detail_scale_m: f64,
    detail_seed: i64,
    values: PackedFloat32Array,
    rows: usize,
    cols: usize,
    scale: f64,
    scale_multiplier: f64,
    profile_macro_relief_scale: f64,
    profile_kernel_relief_strength: f64,
    profile_mountain_boost: f64,
    profile_regional_scale_multiplier: f64,
    profile_valley_bias_strength: f64,
    angle_i: i64,
    offset_u: f64,
    offset_v: f64,
}

#[derive(Clone, Copy)]
struct NativeProfile {
    macro_relief_scale: f64,
    kernel_relief_strength: f64,
    mountain_boost: f64,
    regional_scale_multiplier: f64,
    valley_bias_strength: f64,
}

impl Default for NativeProfile {
    fn default() -> Self {
        Self {
            macro_relief_scale: 1.0,
            kernel_relief_strength: 1.0,
            mountain_boost: 1.0,
            regional_scale_multiplier: 1.0,
            valley_bias_strength: 1.0,
        }
    }
}

fn parse_corners(corner_entries: &AnyArray) -> Result<Vec<PreparedCorner>, String> {
    if corner_entries.len() != 4 {
        return Err(format!("corner_count:{} expected:4", corner_entries.len()));
    }
    let mut corners = Vec::with_capacity(corner_entries.len());
    for corner_index in 0..corner_entries.len() {
        let corner: VarDictionary = corner_entries
            .get(corner_index)
            .ok_or_else(|| format!("missing_corner:{corner_index}"))?
            .to();
        let entries_array: AnyArray = dict_array(&corner, "entries")?;
        if entries_array.is_empty() {
            return Err(format!("entries_empty:{corner_index}"));
        }
        let mut entries = Vec::with_capacity(entries_array.len());
        for entry_index in 0..entries_array.len() {
            let entry: VarDictionary = entries_array
                .get(entry_index)
                .ok_or_else(|| format!("missing_entry:{corner_index}:{entry_index}"))?
                .to();
            let values = dict_packed_f32(&entry, "values")?;
            let rows = dict_i64(&entry, "rows", 0).max(0) as usize;
            let cols = dict_i64(&entry, "cols", 0).max(0) as usize;
            if rows < 2 || cols < 2 {
                return Err(format!(
                    "entry_shape:{corner_index}:{entry_index} rows:{rows} cols:{cols}"
                ));
            }
            let expected_values = rows
                .checked_mul(cols)
                .ok_or_else(|| format!("entry_shape_overflow:{corner_index}:{entry_index}"))?;
            if values.len() != expected_values {
                return Err(format!(
                    "entry_values_size:{corner_index}:{entry_index} size:{} expected:{expected_values}",
                    values.len()
                ));
            }
            let bias = dict_f64(&entry, "bias", 0.0);
            let runtime_weight = dict_f64(&entry, "runtime_weight", 1.0);
            let moderation = dict_f64(&entry, "moderation", 1.0);
            let relief_scale_m = dict_f64(&entry, "relief_scale_m", 0.0);
            let detail_scale_m = dict_f64(&entry, "detail_scale_m", 0.0);
            let scale = dict_f64(&entry, "scale", 1.0);
            let scale_multiplier = dict_f64(&entry, "scale_multiplier", 1.0);
            let profile_macro_relief_scale = dict_f64(&entry, "profile_macro_relief_scale", 1.0);
            let profile_kernel_relief_strength =
                dict_f64(&entry, "profile_kernel_relief_strength", 1.0);
            let profile_mountain_boost = dict_f64(&entry, "profile_mountain_boost", 1.0);
            let profile_regional_scale_multiplier =
                dict_f64(&entry, "profile_regional_scale_multiplier", 1.0);
            let profile_valley_bias_strength =
                dict_f64(&entry, "profile_valley_bias_strength", 1.0);
            let offset_u = dict_f64(&entry, "offset_u", 0.0);
            let offset_v = dict_f64(&entry, "offset_v", 0.0);
            let numeric_values = [
                bias,
                runtime_weight,
                moderation,
                relief_scale_m,
                detail_scale_m,
                scale,
                scale_multiplier,
                profile_macro_relief_scale,
                profile_kernel_relief_strength,
                profile_mountain_boost,
                profile_regional_scale_multiplier,
                profile_valley_bias_strength,
                offset_u,
                offset_v,
            ];
            if numeric_values.iter().any(|value| !value.is_finite()) {
                return Err(format!("entry_nonfinite:{corner_index}:{entry_index}"));
            }
            if scale <= 0.0 {
                return Err(format!(
                    "entry_scale:{corner_index}:{entry_index} value:{scale}"
                ));
            }
            entries.push(PreparedEntry {
                family: dict_string(&entry, "family", ""),
                bias,
                runtime_weight,
                moderation,
                relief_scale_m,
                detail_scale_m,
                detail_seed: dict_i64(&entry, "detail_seed", 0),
                values,
                rows,
                cols,
                scale,
                scale_multiplier,
                profile_macro_relief_scale,
                profile_kernel_relief_strength,
                profile_mountain_boost,
                profile_regional_scale_multiplier,
                profile_valley_bias_strength,
                angle_i: dict_i64(&entry, "angle_i", 0),
                offset_u,
                offset_v,
            });
        }
        corners.push(PreparedCorner { entries });
    }
    Ok(corners)
}

fn dict_array(dict: &VarDictionary, key: &str) -> Result<AnyArray, String> {
    dict.get(key)
        .map(|value| value.to::<AnyArray>())
        .ok_or_else(|| format!("missing_array:{key}"))
}

fn dict_packed_f32(dict: &VarDictionary, key: &str) -> Result<PackedFloat32Array, String> {
    dict.get(key)
        .map(|value| value.to::<PackedFloat32Array>())
        .ok_or_else(|| format!("missing_packed_float32:{key}"))
}

fn dict_i64(dict: &VarDictionary, key: &str, fallback: i64) -> i64 {
    dict.get(key)
        .map(|value| value.to::<i64>())
        .unwrap_or(fallback)
}

fn dict_f64(dict: &VarDictionary, key: &str, fallback: f64) -> f64 {
    dict.get(key)
        .map(|value| value.to::<f64>())
        .unwrap_or(fallback)
}

fn dict_string(dict: &VarDictionary, key: &str, fallback: &str) -> String {
    dict.get(key)
        .map(|value| value.to::<GString>().to_string())
        .unwrap_or_else(|| fallback.to_string())
}

fn sample_height_with_corners(
    x: f64,
    z: f64,
    world_seed: i64,
    region_size_m: f64,
    corners: &[PreparedCorner],
    corner_weights: &[f64; 4],
) -> f32 {
    let profile = profile_from_corners(corners);
    let regional_scale = profile.regional_scale_multiplier.max(0.000001);
    let sample_x = x / regional_scale;
    let sample_z = z / regional_scale;
    let continent = fbm(sample_x, sample_z, 52000.0, world_seed + 3, 4);
    let upland = smoothstep_unit((continent + 0.2) / 0.75);
    let basin = 1.0 - smoothstep_unit((continent + 0.05) / 0.55);
    let mut macro_height = continent * 560.0
        + fbm(sample_x, sample_z, 26000.0, world_seed, 4) * 430.0
        + fbm(
            sample_x + 2300.0,
            sample_z - 1100.0,
            12000.0,
            world_seed + 11,
            3,
        ) * 140.0;
    let ridge = ridged_noise(
        sample_x * 0.8 + sample_z * 0.15,
        sample_z * 0.65 - sample_x * 0.1,
        18000.0,
        world_seed + 37,
        3,
    );
    macro_height += ridge * (190.0 + upland * 230.0);
    macro_height -= basin * 170.0;
    macro_height *= profile.macro_relief_scale;

    let mut detail = 0.0;
    let mut relief = 0.0;
    for (corner_index, corner) in corners.iter().enumerate() {
        let corner_weight = corner_weights[corner_index];
        if corner_weight <= 0.00000001 {
            continue;
        }
        for entry in &corner.entries {
            let weight = corner_weight * entry.bias;
            let sampled = sample_kernel_cached(entry, x, z, region_size_m, regional_scale);
            relief += sampled
                * weight
                * entry.runtime_weight
                * entry.moderation
                * entry.relief_scale_m
                * (0.58 + upland * 0.38)
                * profile.kernel_relief_strength
                * family_relief_boost(&entry.family, profile.mountain_boost);
            detail += fbm(sample_x, sample_z, 3000.0, entry.detail_seed, 2)
                * weight
                * entry.runtime_weight
                * entry.moderation
                * entry.detail_scale_m
                * 0.82;
        }
    }

    let valleys = valley_mask(sample_x, sample_z, world_seed);
    let valley_cut = valleys * (110.0 + upland * 130.0) * profile.valley_bias_strength;
    let valley_floor_noise = fbm(sample_x, sample_z, 4200.0, world_seed + 401, 2) * 24.0 * valleys;
    (macro_height + relief + detail - valley_cut + valley_floor_noise) as f32
}

fn profile_from_corners(corners: &[PreparedCorner]) -> NativeProfile {
    for corner in corners {
        for entry in &corner.entries {
            return NativeProfile {
                macro_relief_scale: entry.profile_macro_relief_scale,
                kernel_relief_strength: entry.profile_kernel_relief_strength,
                mountain_boost: entry.profile_mountain_boost,
                regional_scale_multiplier: entry.profile_regional_scale_multiplier,
                valley_bias_strength: entry.profile_valley_bias_strength,
            };
        }
    }
    NativeProfile::default()
}

fn family_relief_boost(family: &str, mountain_boost: f64) -> f64 {
    if (mountain_boost - 1.0).abs() <= 0.000001 {
        return 1.0;
    }
    match family {
        "mountain" | "glacial" | "volcanic" => mountain_boost,
        _ => 1.0,
    }
}

fn sample_kernel_cached(
    entry: &PreparedEntry,
    x: f64,
    z: f64,
    region_size_m: f64,
    regional_scale_multiplier: f64,
) -> f64 {
    if entry.rows < 2
        || entry.cols < 2
        || entry.values.len() != entry.rows * entry.cols
        || !entry.scale.is_finite()
        || entry.scale <= 0.0
    {
        return 0.0;
    }
    let mut scale = entry.scale;
    if (regional_scale_multiplier - 1.0).abs() > 0.000001 && entry.scale_multiplier > 0.0 {
        scale = (region_size_m * regional_scale_multiplier).max(0.000001) * entry.scale_multiplier;
    }
    let mut u = x / scale;
    let mut v = z / scale;
    match entry.angle_i {
        1 => {
            let old_u = u;
            u = v;
            v = -old_u;
        }
        2 => {
            u = -u;
            v = -v;
        }
        3 => {
            let old_u = u;
            u = -v;
            v = old_u;
        }
        _ => {}
    }
    u += entry.offset_u;
    v += entry.offset_v;
    bilinear_sample_values(entry.values.as_slice(), entry.rows, entry.cols, u, v)
}

fn bilinear_sample_values(values: &[f32], rows: usize, cols: usize, u: f64, v: f64) -> f64 {
    let mu = 1.0 - (fposmod(u, 2.0) - 1.0).abs();
    let mv = 1.0 - (fposmod(v, 2.0) - 1.0).abs();
    let px = mu * (cols - 1) as f64;
    let py = mv * (rows - 1) as f64;
    let x0 = (px.floor() as usize).min(cols - 1);
    let y0 = (py.floor() as usize).min(rows - 1);
    let x1 = (x0 + 1).min(cols - 1);
    let y1 = (y0 + 1).min(rows - 1);
    let tx = px - x0 as f64;
    let ty = py - y0 as f64;
    let a = values[y0 * cols + x0] as f64;
    let b = values[y0 * cols + x1] as f64;
    let c = values[y1 * cols + x0] as f64;
    let d = values[y1 * cols + x1] as f64;
    lerp(lerp(a, b, tx), lerp(c, d, tx), ty)
}

fn valley_mask(x: f64, z: f64, world_seed: i64) -> f64 {
    let broad = ridged_noise(x + 5000.0, z - 3100.0, 18000.0, world_seed + 101, 4);
    let tributary = ridged_noise(
        x * 1.15 - z * 0.10,
        z * 0.9 + x * 0.08,
        6200.0,
        world_seed + 211,
        3,
    );
    let combined = broad * 0.72 + tributary * 0.28;
    smoothstep_unit((combined - 0.16) / 0.52)
}

fn ridged_noise(x: f64, z: f64, scale_m: f64, world_seed: i64, octaves: i64) -> f64 {
    let value = fbm(x, z, scale_m, world_seed, octaves);
    let ridged = 1.0 - value.abs();
    ridged * ridged * 2.0 - 1.0
}

fn fbm(x: f64, z: f64, scale_m: f64, world_seed: i64, octaves: i64) -> f64 {
    let mut total = 0.0;
    let mut amp = 1.0;
    let mut norm = 0.0;
    for octave in 0..octaves {
        total += value_noise(
            x,
            z,
            scale_m / ((1_i64 << octave) as f64),
            world_seed,
            octave,
        ) * amp;
        norm += amp;
        amp *= 0.5;
    }
    total / norm.max(0.000001)
}

fn value_noise(x: f64, z: f64, scale_m: f64, world_seed: i64, salt: i64) -> f64 {
    let fx = x / scale_m;
    let fz = z / scale_m;
    let ix = fx.floor() as i64;
    let iz = fz.floor() as i64;
    let tx = fade(fx - ix as f64);
    let tz = fade(fz - iz as f64);
    let a = hash_grid(ix, iz, world_seed, salt);
    let b = hash_grid(ix + 1, iz, world_seed, salt);
    let c = hash_grid(ix, iz + 1, world_seed, salt);
    let d = hash_grid(ix + 1, iz + 1, world_seed, salt);
    lerp(lerp(a, b, tx), lerp(c, d, tx), tz) * 2.0 - 1.0
}

fn hash_grid(ix: i64, iz: i64, world_seed: i64, salt: i64) -> f64 {
    let mask = 0xffff_ffff_i128;
    let mut n = (ix as i128 * 374_761_393_i128
        + iz as i128 * 668_265_263_i128
        + world_seed as i128 * 1_442_695_041_i128
        + salt as i128 * 69_069_i128)
        & mask;
    n = (n ^ (n >> 13)) * 1_274_126_177_i128;
    n = (n ^ (n >> 16)) & mask;
    (n as f64) / 4_294_967_295.0
}

fn fade(t: f64) -> f64 {
    t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
}

fn smoothstep_unit(t: f64) -> f64 {
    let v = t.clamp(0.0, 1.0);
    v * v * (3.0 - 2.0 * v)
}

fn fposmod(value: f64, modulo: f64) -> f64 {
    value.rem_euclid(modulo)
}

fn lerp(a: f64, b: f64, t: f64) -> f64 {
    a + (b - a) * t
}
