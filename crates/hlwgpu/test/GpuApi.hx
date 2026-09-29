class GpuApi {
	static function request(instance:gpu.GpuInstance):ash.Future<gpu.GpuAdapter> {
		return instance.requestAdapter(gpu.Power.HighPerformance);
	}

	static function main() {
		var mode:Int = gpu.MapMode.READ;
		if (mode != 1)
			throw "generated enum values drifted";
	}
}
