extends RefCounted

## Original, deterministic PCM synthesis. No samples, recordings, music or game rips.
## Shared semantic cues: card identity, stats and private choices never select a sound.
const RATE := 22050
const DURATIONS := {"summon": 0.85, "attack": 0.72, "position": 0.65, "destroy": 0.9}

static func synthesize(kind: String) -> AudioStreamWAV:
	if not DURATIONS.has(kind): return null
	var duration: float = DURATIONS[kind]
	var samples := int(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 46729 # Local generator; never consume the duel's seeded RNG.
	var low_noise := 0.0
	for i in range(samples):
		var t := float(i) / RATE
		var p := t / duration
		var noise := random.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, noise, 0.13)
		var sample := 0.0
		match kind:
			"summon":
				# Card flick, rising energy, then a warm seal and crystalline afterglow.
				var flick := exp(-pow((p - 0.08) * 28.0, 2.0))
				var rise := sin(p * PI) * (1.0 - smoothstep(0.40, 0.75, p))
				var seal := maxf(0.0, t - 0.31)
				sample = low_noise * flick * 0.55 + low_noise * rise * 0.55
				sample += sin(TAU * (140.0 * t + 240.0 * t * t)) * rise * 0.15
				if t >= 0.31:
					sample += sin(TAU * (100.0 * seal - 32.0 * seal * seal)) * exp(-seal * 9.0) * 0.34
					for frequency in [659.25, 987.77, 1318.51]:
						sample += sin(TAU * frequency * seal) * exp(-seal * 7.0) * 0.045
			"attack":
				# Wind-up and rushing slash, not a damage/LP result or a guaranteed hit.
				var sweep := exp(-pow((p - 0.39) * 6.5, 2.0))
				var edge := exp(-pow((p - 0.52) * 17.0, 2.0))
				sample = low_noise * sweep * 1.0 + (noise - low_noise) * edge * 0.16
				sample += sin(TAU * (360.0 * t - 170.0 * t * t)) * sweep * 0.13
				sample += sin(TAU * 82.0 * t) * edge * 0.28
			"position":
				# Short papery turn and quiet mechanical lock; no hidden identity cue.
				var turn := sin(p * PI) * (1.0 - smoothstep(0.45, 0.90, p))
				var lock := exp(-pow((p - 0.61) * 30.0, 2.0))
				sample = low_noise * turn * 0.62 + noise * lock * 0.09
				sample += sin(TAU * (195.0 * t - 70.0 * t * t)) * turn * 0.08
				sample += sin(TAU * 420.0 * t) * lock * 0.12
			"destroy":
				# Three granular fractures, a low break and a falling, airy decay.
				var cracks := exp(-pow((p - 0.12) * 38.0, 2.0))
				cracks += exp(-pow((p - 0.22) * 42.0, 2.0)) * 0.60
				cracks += exp(-pow((p - 0.32) * 46.0, 2.0)) * 0.35
				var dust := smoothstep(0.10, 0.27, p) * pow(1.0 - p, 2.0)
				sample = noise * cracks * 0.30 + low_noise * dust * 0.65
				sample += sin(TAU * (92.0 * t - 35.0 * t * t)) * dust * 0.35
				sample += sin(TAU * (1700.0 * t - 650.0 * t * t)) * cracks * 0.055
		# Smooth endpoints, conservative headroom and one voice avoid clipping stacks.
		sample *= smoothstep(0.0, 0.008, t) * smoothstep(0.0, 0.035, duration - t - 1.0 / RATE)
		bytes.encode_s16(i * 2, int(clampf(sample, -0.85, 0.85) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream
