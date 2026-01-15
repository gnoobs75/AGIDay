class_name GridStability
extends RefCounted
## GridStability calculates power grid stability metrics for strategic planning.

signal stability_changed(faction_id: String, new_stability: float)
signal vulnerability_detected(faction_id: String, vulnerability: Dictionary)
signal grid_at_risk(faction_id: String, risk_level: float)

## Stability thresholds
const STABLE_THRESHOLD := 0.75      ## Above this = stable grid
const WARNING_THRESHOLD := 0.50     ## Above this = warning level
const CRITICAL_THRESHOLD := 0.25    ## Above this = critical level

## Risk levels
enum RiskLevel {
	STABLE,
	WARNING,
	CRITICAL,
	FAILING
}

## Cached stability data (faction_id -> StabilityData)
var _faction_stability: Dictionary = {}

## References
var _power_api = null  # PowerGridAPI
var _consumer_manager: PowerConsumerManager = null


func _init() -> void:
	pass


## Set references.
func set_power_api(api) -> void:
	_power_api = api


func set_consumer_manager(manager: PowerConsumerManager) -> void:
	_consumer_manager = manager


## Calculate stability for faction.
func calculate_stability(faction_id: String) -> Dictionary:
	var stability_data := {
		"faction_id": faction_id,
		"stability_score": 0.0,
		"risk_level": RiskLevel.FAILING,
		"generation": 0.0,
		"consumption": 0.0,
		"balance": 0.0,
		"reserve_ratio": 0.0,
		"vulnerabilities": [],
		"recommendations": []
	}

	if _power_api == null:
		return stability_data

	# Get power status
	var status: Dictionary = _power_api.get_faction_power_status(faction_id)
	var generation: float = status.get("generation", 0.0)
	var consumption := 0.0

	if _consumer_manager != null:
		consumption = _consumer_manager.get_faction_consumption(faction_id)
	else:
		consumption = status.get("demand", 0.0)

	stability_data["generation"] = generation
	stability_data["consumption"] = consumption
	stability_data["balance"] = generation - consumption

	# Calculate reserve ratio
	if consumption > 0.0:
		stability_data["reserve_ratio"] = generation / consumption
	else:
		stability_data["reserve_ratio"] = 1.0 if generation > 0.0 else 0.0

	# Calculate stability score (0.0 to 1.0)
	var stability_score := _calculate_stability_score(status, stability_data["reserve_ratio"])
	stability_data["stability_score"] = stability_score

	# Determine risk level
	stability_data["risk_level"] = _get_risk_level(stability_score)

	# Identify vulnerabilities
	stability_data["vulnerabilities"] = _identify_vulnerabilities(faction_id, status)

	# Generate recommendations
	stability_data["recommendations"] = _generate_recommendations(stability_data)

	# Cache and emit
	var old_stability: float = _faction_stability.get(faction_id, {}).get("stability_score", 0.0)
	_faction_stability[faction_id] = stability_data

	if abs(stability_score - old_stability) > 0.05:
		stability_changed.emit(faction_id, stability_score)

	if stability_data["risk_level"] >= RiskLevel.CRITICAL:
		grid_at_risk.emit(faction_id, stability_score)

	return stability_data


## Calculate stability score.
func _calculate_stability_score(status: Dictionary, reserve_ratio: float) -> float:
	var score := 0.0

	# Factor 1: Reserve ratio (40% weight)
	var reserve_score := clampf(reserve_ratio, 0.0, 2.0) / 2.0
	score += reserve_score * 0.4

	# Factor 2: Plant health (30% weight)
	var plants: Dictionary = status.get("plants", {})
	var operational: int = plants.get("operational", 0)
	var total: int = plants.get("total", 1)
	var plant_health := float(operational) / float(maxi(total, 1))
	score += plant_health * 0.3

	# Factor 3: District power coverage (30% weight)
	var districts: Dictionary = status.get("districts", {})
	var powered: int = districts.get("powered", 0)
	var total_districts: int = districts.get("total", 1)
	var coverage := float(powered) / float(maxi(total_districts, 1))
	score += coverage * 0.3

	return clampf(score, 0.0, 1.0)


## Get risk level from stability score.
func _get_risk_level(stability_score: float) -> int:
	if stability_score >= STABLE_THRESHOLD:
		return RiskLevel.STABLE
	elif stability_score >= WARNING_THRESHOLD:
		return RiskLevel.WARNING
	elif stability_score >= CRITICAL_THRESHOLD:
		return RiskLevel.CRITICAL
	else:
		return RiskLevel.FAILING


## Get risk level name.
func get_risk_level_name(risk_level: int) -> String:
	match risk_level:
		RiskLevel.STABLE:
			return "stable"
		RiskLevel.WARNING:
			return "warning"
		RiskLevel.CRITICAL:
			return "critical"
		RiskLevel.FAILING:
			return "failing"
		_:
			return "unknown"


## Identify vulnerabilities.
func _identify_vulnerabilities(faction_id: String, status: Dictionary) -> Array:
	var vulnerabilities: Array = []

	# Check for single point of failure (only one plant)
	var plants: Dictionary = status.get("plants", {})
	if plants.get("operational", 0) == 1:
		var vuln := {
			"type": "single_point_of_failure",
			"severity": "high",
			"description": "Only one operational power plant"
		}
		vulnerabilities.append(vuln)
		vulnerability_detected.emit(faction_id, vuln)

	# Check for low reserve margin
	var ratio: float = status.get("ratio", 0.0)
	if ratio < 1.1 and ratio > 0.0:
		vulnerabilities.append({
			"type": "low_reserve_margin",
			"severity": "medium",
			"description": "Power generation barely meets demand"
		})

	# Check for damaged infrastructure
	var destroyed: int = plants.get("destroyed", 0)
	if destroyed > 0:
		vulnerabilities.append({
			"type": "damaged_infrastructure",
			"severity": "medium",
			"description": "%d power plant(s) destroyed" % destroyed
		})

	# Check for districts in blackout
	var districts: Dictionary = status.get("districts", {})
	var blackout: int = districts.get("blackout", 0)
	if blackout > 0:
		vulnerabilities.append({
			"type": "active_blackouts",
			"severity": "high",
			"description": "%d district(s) in blackout" % blackout
		})

	return vulnerabilities


## Generate recommendations.
func _generate_recommendations(p_stability_data: Dictionary) -> Array:
	var recommendations: Array = []
	var risk_level: int = p_stability_data["risk_level"]
	var balance: float = p_stability_data["balance"]

	if risk_level >= RiskLevel.CRITICAL:
		recommendations.append("URGENT: Build additional power plants immediately")

	if balance < 0:
		var deficit := abs(balance)
		recommendations.append("Power deficit of %.0f - reduce consumption or add generation" % deficit)

	if p_stability_data["reserve_ratio"] < 1.2:
		recommendations.append("Build reserve capacity - target 20%% over demand")

	for vuln in p_stability_data["vulnerabilities"]:
		match vuln["type"]:
			"single_point_of_failure":
				recommendations.append("Build backup power plant to reduce vulnerability")
			"damaged_infrastructure":
				recommendations.append("Repair damaged power plants to restore capacity")
			"active_blackouts":
				recommendations.append("Restore power to blacked-out districts")

	return recommendations


## Get cached stability for faction.
func get_stability(faction_id: String) -> Dictionary:
	if _faction_stability.has(faction_id):
		return _faction_stability[faction_id]
	return calculate_stability(faction_id)


## Get stability score for faction.
func get_stability_score(faction_id: String) -> float:
	return get_stability(faction_id).get("stability_score", 0.0)


## Get risk level for faction.
func get_risk_level(faction_id: String) -> int:
	return get_stability(faction_id).get("risk_level", RiskLevel.FAILING)


## Check if grid is stable.
func is_grid_stable(faction_id: String) -> bool:
	return get_risk_level(faction_id) == RiskLevel.STABLE


## Check if grid is at risk.
func is_grid_at_risk(faction_id: String) -> bool:
	return get_risk_level(faction_id) >= RiskLevel.CRITICAL


## Update all faction stabilities.
func update_all() -> void:
	for faction_id in _faction_stability:
		calculate_stability(faction_id)


## Serialization.
func to_dict() -> Dictionary:
	var stability_data: Dictionary = {}
	for faction_id in _faction_stability:
		stability_data[faction_id] = _faction_stability[faction_id].duplicate()

	return {
		"faction_stability": stability_data
	}


func from_dict(data: Dictionary) -> void:
	_faction_stability.clear()
	var stability_data: Dictionary = data.get("faction_stability", {})
	for faction_id in stability_data:
		_faction_stability[faction_id] = stability_data[faction_id].duplicate()


## Get summary for debugging.
func get_summary() -> Dictionary:
	var risk_counts: Dictionary = {}
	for level in RiskLevel.values():
		risk_counts[get_risk_level_name(level)] = 0

	for faction_id in _faction_stability:
		var risk: int = _faction_stability[faction_id]["risk_level"]
		var name := get_risk_level_name(risk)
		risk_counts[name] += 1

	return {
		"tracked_factions": _faction_stability.size(),
		"risk_distribution": risk_counts
	}
