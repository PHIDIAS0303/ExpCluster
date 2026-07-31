import * as lib from "@clusterio/lib";

/**
 * Convert a legacy role action into its clusterio permission name.
 *
 * The exp_roles lua module applies the same transform, so existing call sites such as
 * `Roles.player_allowed(player, "gui/warp-list/add")` keep working unchanged.
 *
 * @param action - Legacy action such as `gui/warp-list/add` or `fast-tree-decon`.
 * @returns Permission name such as `exp_scenario.gui.warp_list.add`.
 */
export function permissionFromAction(action: string) {
	const body = action.replace(/-/g, "_").replace(/\//g, ".");
	return `exp_scenario.${body.includes(".") ? body : `action.${body}`}`;
}

/**
 * Convert a legacy role flag into its clusterio permission name.
 *
 * @param flag - Legacy flag such as `report-immune`.
 * @returns Permission name such as `exp_scenario.flag.report_immune`.
 */
export function permissionFromFlag(flag: string) {
	return `exp_scenario.flag.${flag.replace(/-/g, "_")}`;
}

/** Legacy actions which map onto core clusterio permissions rather than scenario ones. */
export const coreActionPermissions: Record<string, string> = {
	"command/assign-role": "core.user.update_roles",
	"command/unassign-role": "core.user.update_roles",
	"command/get-roles": "core.role.list",
};

/** Legacy action, user facing title, description, and whether every player gets it. */
type ActionDefinition = [action: string, title: string, description: string, grantByDefault?: boolean];

const actions: ActionDefinition[] = [
	["bypass-entity-protection", "Bypass entity protection", "Remove entities that the protection filter would block."],
	["bypass-nukeprotect", "Bypass nuke protection", "Use nukes without the nuke protection restrictions."],
	["command/_rcon", "/_rcon", "Execute arbitrary code within a custom environment."],
	["command/admin-chat", "/admin-chat", "Sends a message in chat that only admins can see."],
	["command/artillery", "/artillery", "Automaticly select enemy target with artillery."],
	["command/ban", "/ban", "Ban a player from the cluster via the player list."],
	["command/bring", "/bring", "Teleports a player to you."],
	["command/chat-commands", "Chat commands", "Use the chat command prefix to trigger auto replies."],
	["command/clear-blueprints", "/clear-blueprints", "Clear all blueprints."],
	["command/clear-blueprints-surface", "/clear-blueprints-surface", "Clear all blueprints on the current surface."],
	["command/clear-ground-items", "/clear-ground-items", "Clear all items on the ground."],
	["command/clear-inventory", "/clear-inventory", "Clear a player's inventory, moving all items to spawn."],
	["command/clear-last-warnings", "/clear-last-warnings", "Clears the last warning from a player."],
	["command/clear-pollution", "/clear-pollution", "Clear pollution from your current surface, or another surface."],
	["command/clear-reports", "/clear-reports", "Clears all reports from a player or just the report from one player."],
	["command/clear-script-warnings", "/clear-script-warnings", "Clears all script warnings from a player."],
	["command/clear-tag/always", "/clear-tag (any player)", "Clear the tag of any player, not just your own."],
	["command/clear-warnings", "/clear-warnings", "Clears all warnings (and script warnings) from a player."],
	["command/collectdata", "/collectdata", "Collect data for RCON usage."],
	["command/commands", "/commands", "List and search all commands for a keyword.", true],
	["command/connect", "/connect", "Connect to another server.", true],
	["command/connect-all", "/connect-all", "Connect all players to another server."],
	["command/connect-player", "/connect-player", "Connect a player to a different server."],
	["command/create-report", "/create-report", "Reports a player and notifies moderators.", true],
	["command/create-warning", "/create-warning", "Gives a warning to a player; may lead to automatic script action."],
	["command/data-preference", "/data-preference", "Allows you to set/get your data saving preference.", true],
	["command/debug", "/debug", "Opens the debug gui."],
	["command/follow", "/follow", "Start following a player in spectator."],
	["command/get-home", "/get-home", "Returns your current home location."],
	["command/get-reports", "/get-reports", "List the reports against a player, or against every player."],
	["command/get-warnings", "/get-warnings", "List the warnings against a player, or against every player."],
	["command/give-warning", "/give-warning", "Give a player a warning via the player list."],
	["command/goto", "/goto", "Teleports you to a player."],
	["command/home", "/home", "Teleports you to your home location."],
	["command/jail", "/jail", "Puts a player into jail and removes all other roles."],
	["command/kick", "/kick", "Kick a player from the server via the player list."],
	["command/kill", "/kill", "Kills yourself or another player."],
	["command/kill-enemies", "/kill-enemies", "Kill all enemy units."],
	["command/kill/always", "/kill (any player)", "Kill any player, not just yourself."],
	["command/lawnmower", "/lawnmower", "Clean up biter corpse, decoratives and nuclear hole."],
	["command/locate", "/locate", "Opens remote view at the location of the player's last location.", true],
	["command/me", "/me", "Sends an action message in the chat."],
	["command/protect-area", "/protect-area", "Toggles area protection selection, hold shift to remove protection."],
	["command/protect-entity", "/protect-entity", "Toggles entity protection selection, hold shift to remove protection."],
	["command/protect-tag", "/protect-tag", "Toggles protected tag mode, edit and create protected map tags."],
	["command/rainbow", "/rainbow", "Sends an rainbow message in the chat."],
	["command/ratio", "/ratio", "Get the input and output ratios of the selected machine.", true],
	["command/remove-enemies", "/remove-enemies", "Remove all enemy spawners."],
	["command/remove-join-message", "/remove-join-message", "Removes you custom join message."],
	["command/repair", "/repair", "Repairs entities on your force around you."],
	["command/research-all", "/research-all", "Research all technology for your force, or another force."],
	["command/return", "/return", "Teleports you to previous location."],
	["command/save-data", "/save-data", "Writes all your player data to a file on your computer.", true],
	["command/save-quickbar", "/save-quickbar", "Saves your Quickbar preset items to file."],
	["command/search", "/search", "Display players sorted by the quantity of an item held and playtime."],
	["command/search-amount", "/search-amount", "Display players sorted by the quantity of an item held."],
	["command/search-online", "/search-online", "Display online players sorted by item count and playtime."],
	["command/search-recent", "/search-recent", "Display players who hold an item sorted by join time."],
	["command/server-ups", "/server-ups", "Toggle the server UPS display.", true],
	["command/set-always-day", "/set-always-day", "Set always day for your current surface, or another surface."],
	["command/set-bot-queue", "/set-bot-queue", "Get / Set the construction bot queue limits."],
	["command/set-cheat-mode", "/set-cheat-mode", "Set cheat mode for your player, or another player."],
	["command/set-friendly-fire", "/set-friendly-fire", "Set friendly fire for your force, or another force."],
	["command/set-game-speed", "/set-game-speed", "Set or get the current game speed."],
	["command/set-home", "/set-home", "Sets your home location to your current position."],
	["command/set-join-message", "/set-join-message", "Sets / Gets your custom join message."],
	["command/set-pollution-enabled", "/set-pollution-enabled", "Set polution enabled state for this game."],
	["command/set-trains-to-automatic", "/set-trains-to-automatic", "Set all trains without passengers to automatic."],
	["command/spawn", "/spawn", "Teleport to spawn."],
	["command/spawn/always", "/spawn (any player)", "Teleport any player to spawn, not just yourself."],
	["command/spectate", "/spectate", "Toggles spectator mode."],
	["command/tag", "/tag", "Sets your player tag.", true],
	["command/tag-clear", "/tag-clear", "Clears your tag. Or another player if you are admin.", true],
	["command/tag-color", "/tag-color", "Sets your player tag color."],
	["command/teleport", "/teleport", "Teleports a player to another player."],
	["command/unjail", "/unjail", "Removes a player from jail and restores their previous roles."],
	["command/vlayer-info", "/vlayer-info", "Print all vlayer information."],
	["command/waterfill", "/waterfill", "Replace tiles with shallow water."],
	["fast-tree-decon", "Fast tree deconstruction", "Deconstruct trees and rocks instantly over a large area."],
	["gui/autofill", "Autofill", "Open the autofill GUI, which fills placed entities from your inventory.", true],
	["gui/bonus", "Bonus", "Open the bonus GUI to adjust your personal bonuses."],
	["gui/module", "Module inserter", "Open the module inserter GUI.", true],
	["gui/player-list", "Player list", "Open the player list GUI.", true],
	["gui/playerdata", "Player statistics", "Open the player statistics GUI."],
	["gui/production", "Production statistics", "Open the production statistics GUI.", true],
	["gui/readme", "Readme", "Open the server readme GUI.", true],
	["gui/research", "Research milestones", "Open the research milestones GUI.", true],
	["gui/rocket-info", "Rocket info", "Open the rocket info GUI.", true],
	["gui/rocket-info/remote_launch", "Rocket info: remote launch", "Launch rockets remotely from the rocket info GUI."],
	["gui/rocket-info/toggle-active", "Rocket info: toggle active", "Toggle whether a silo launches automatically."],
	["gui/science-info", "Science production", "Open the science production GUI.", true],
	["gui/surveillance", "Surveillance", "Open the surveillance GUI showing remote camera views."],
	["gui/task-list", "Task list", "Open the task list GUI.", true],
	["gui/task-list/add", "Task list: add", "Add new tasks to the task list."],
	["gui/task-list/edit", "Task list: edit", "Edit and remove existing tasks on the task list."],
	["gui/tool", "Quick actions", "Open the quick actions GUI."],
	["gui/vlayer", "Virtual layer", "Open the virtual layer GUI.", true],
	["gui/vlayer-edit", "Virtual layer: edit", "Use the edit controls in the virtual layer GUI."],
	["gui/warp-list", "Warp list", "Open the warp list GUI and warp between locations.", true],
	["gui/warp-list/add", "Warp list: add", "Add new warp points to the warp list."],
	["gui/warp-list/bypass-cooldown", "Warp list: bypass cooldown", "Warp without waiting for the warp cooldown."],
	["gui/warp-list/bypass-proximity", "Warp list: bypass proximity", "Warp without standing near a warp point."],
	["gui/warp-list/edit", "Warp list: edit", "Edit and remove existing warp points."],
	["standard-decon", "Standard deconstruction", "Deconstruct trees and rocks."],
];

const flags: ActionDefinition[] = [
	["deconlog-bypass", "Deconstruction log bypass", "Be excluded from the deconstruction log."],
	["defer_role_changes", "Defer role changes", "Hold back role changes until this role is removed; used by Jail."],
	["instant-respawn", "Instant respawn", "Respawn after two seconds instead of the default delay."],
	["is_admin", "Factorio admin", "Be promoted to Factorio admin while holding a role with this flag."],
	["is_spectator", "Spectator", "Be placed into Factorio spectator mode."],
	["is_system", "System commands", "Unlock system commands such as /_rcon and /_sudo."],
	["report-immune", "Report immune", "Be immune to being reported by other players."],
];

for (const [action, title, description, grantByDefault] of actions) {
	lib.definePermission({ name: permissionFromAction(action), title, description, grantByDefault });
}

for (const [flag, title, description] of flags) {
	lib.definePermission({ name: permissionFromFlag(flag), title, description });
}
