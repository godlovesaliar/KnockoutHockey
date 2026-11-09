extends Node
## Match settings chosen on the setup screen and read by MatchDirector.

## Overtime modes: "off", "sudden_death", "shootout", "sd_so" (sudden death, then shootout).
var config := default_config()

## Who plays: [{kind: "any"|"kb1"|"kb2"|"pad", pad: int, team: 0|1}]
var humans: Array = [{"kind": "any", "pad": 0, "team": 0}]


static func default_config() -> Dictionary:
	return {
		"format": 5,
		"period_length": 180.0,
		"periods": 3,
		"overtime": "sd_so",
		"ot_length": 180.0,
		"shootout_rounds": 3,
		"offsides": true,
		"icing": true,
		"penalties": true,
		"fighting": true,
		"line_changes": true,
		"difficulty": 0.5,
		"camera": "broadcast",      ## BroadcastCamera play angle
		"camera_follow": false,      ## turn the angle so your team always attacks up
		"home_team": 0,    ## Teams.LIST index
		"away_team": 1,
	}
