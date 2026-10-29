class_name CardAnimationRegistry
extends RefCounted

## Presentation-only plug-in table. Names must already be visible in the viewer snapshot.
## Add a profile with duration(action) and draw(canvas, rect, action, progress, time,
## defense, target). No rules, assets, engine objects or raw card IDs belong in a profile.
const GenericProfile = preload("res://Scripts/presentation/GenericAnimationProfile.gd")
const PortraitProfile = preload("res://Scripts/presentation/PortraitAnimationProfile.gd")
var _fallback = GenericProfile.new()
var _profiles: Dictionary = {"The Portrait's Secret": PortraitProfile.new()}

func register_profile(visible_name: String, profile: RefCounted) -> bool:
	if visible_name.is_empty() or profile == null or not profile.has_method("duration") or not profile.has_method("draw"):
		return false
	_profiles[visible_name] = profile
	return true

func profile_for(card: Dictionary):
	if bool(card.get("hidden", true)) or not bool(card.get("face_up", false)):
		return null
	return _profiles.get(str(card.get("name", "")), _fallback)
