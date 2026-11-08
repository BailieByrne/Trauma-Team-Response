@addField(PreventionSpawnSystem)
private let ttResponse: ref<WETraumaResponse>;

@addField(PreventionSpawnSystem)
private let ttConfig: ref<TraumaTeamConfig>;

@addMethod(PreventionSpawnSystem)
public final func TTGetConfig() -> ref<TraumaTeamConfig> {
  if !IsDefined(this.ttConfig) { this.ttConfig = new TraumaTeamConfig(); };
  return this.ttConfig;
}

@addMethod(PreventionSpawnSystem)
public final func TTSetSetting(key: String, value: Int32) -> Void {
  let config: ref<TraumaTeamConfig> = this.TTGetConfig();
  if Equals(key, "enabled") { config.enabled = value != 0; }
  else if Equals(key, "corpoChance") { config.corpoChance = value; }
  else if Equals(key, "mercChance") { config.mercChance = value; }
  else if Equals(key, "gangChance") { config.gangChance = value; }
  else if Equals(key, "fringeChance") { config.fringeChance = value; }
  else if Equals(key, "silverWeight") { config.silverWeight = value; }
  else if Equals(key, "goldWeight") { config.goldWeight = value; }
  else if Equals(key, "silverDelay") { config.silverDelay = value; }
  else if Equals(key, "goldDelay") { config.goldDelay = value; }
  else if Equals(key, "platinumDelay") { config.platinumDelay = value; };
}

// Called by the CET Native Settings UI after loading its saved JSON and when
// a slider changes. The menu is available in the game's Mods tab.
public exec func TTSetSetting(gi: GameInstance, key: String, value: Int32) -> Void {
  GameInstance.GetPreventionSpawnSystem(gi).TTSetSetting(key, value);
}

@addField(PreventionSpawnSystem)
private let ttPendingCorpse: ref<NPCPuppet>;

@addField(PreventionSpawnSystem)
private let ttPendingPlayer: ref<PlayerPuppet>;

@addField(PreventionSpawnSystem)
private let ttPendingTier: Int32;

@addField(PreventionSpawnSystem)
private let ttPendingLocation: Vector4;

@addMethod(PreventionSpawnSystem)
public final func TTIsPatientNearby(corpse: wref<NPCPuppet>, player: wref<PlayerPuppet>, location: Vector4) -> Bool {
  return IsDefined(corpse) && corpse.IsAttached() && IsDefined(player) && player.IsAttached() && Vector4.Distance2D(player.GetWorldPosition(), location) <= 120.0;
}

@addMethod(PreventionSpawnSystem)
public final func TTPrunePendingResponse() -> Void {
  if IsDefined(this.ttPendingCorpse) && !this.TTIsPatientNearby(this.ttPendingCorpse, this.ttPendingPlayer, this.ttPendingLocation) {
    this.ttPendingCorpse = null;
    this.ttPendingPlayer = null;
    this.ttPendingTier = 0;
    ModLog(n"TraumaTeamSubscriptions", "Dropped queued response; patient unloaded or player left scene");
  };
}

@addMethod(PreventionSpawnSystem)
public final func TTResetForSaveLoad() -> Void {
  let response: ref<WETraumaResponse> = this.ttResponse;
  this.ttResponse = null;
  this.ttPendingCorpse = null;
  this.ttPendingPlayer = null;
  this.ttPendingTier = 0;
  this.ttPendingLocation = Vector4(0.0, 0.0, 0.0, 0.0);
  if IsDefined(response) { response.CancelForSaveLoad(); };
  ModLog(n"TraumaTeamSubscriptions", "Cleared dispatch state for save load");
}

@addMethod(PreventionSpawnSystem)
public final func TTStartResponse(corpse: ref<NPCPuppet>, player: ref<PlayerPuppet>, tier: Int32) -> Bool {
  let config: ref<TraumaTeamConfig> = this.TTGetConfig();
  if !config.enabled { return false; };
  if !IsDefined(corpse) || !IsDefined(player) { return false; };
  if !this.TTIsPatientNearby(corpse, player, corpse.GetWorldPosition()) { return false; };
  // One live recovery and one waiting dispatch at most, globally.
  if IsDefined(this.ttResponse) {
    this.TTPrunePendingResponse();
    if IsDefined(this.ttPendingCorpse) { return false; };
    this.ttPendingCorpse = corpse;
    this.ttPendingPlayer = player;
    this.ttPendingTier = tier;
    this.ttPendingLocation = corpse.GetWorldPosition();
    ModLog(n"TraumaTeamSubscriptions", "Response queued behind active extraction");
    return true;
  };
  let response: ref<WETraumaResponse> = new WETraumaResponse();
  response.system = this;
  response.corpse = corpse;
  response.player = player;
  response.tier = tier;
  response.outdoors = !IsEntityInInteriorArea(corpse);
  response.extraction = corpse.GetWorldPosition();
  response.incidentPosition = corpse.GetWorldPosition();
  this.ttResponse = response;
  let message: SimpleScreenMessage;
  let notifications = GetAllBlackboardDefs().UI_Notifications;
  let blackboard = GameInstance.GetBlackboardSystem(player.GetGame()).Get(notifications);
  message.message = s"TRAUMA TEAM \(response.TierName()): RECOVERY UNIT EN ROUTE (\(response.ArrivalSeconds())s)";
  message.isShown = true;
  message.duration = 5.0;
  blackboard.SetVariant(notifications.OnscreenMessage, ToVariant(message), true);
  GameInstance.GetAudioSystem(player.GetGame()).Play(n"ui_jingle_car_call");
  ModLog(n"TraumaTeamSubscriptions", s"Response requested; outdoors=\(response.outdoors)");
  response.BeginCountdown();
  return true;
}

@addMethod(PreventionSpawnSystem)
public final func TTFinishResponse(response: ref<WETraumaResponse>) -> Void {
  if this.ttResponse != response { return; };
  this.ttResponse = null;
  this.TTPrunePendingResponse();
  if IsDefined(this.ttPendingCorpse) {
    let corpse: ref<NPCPuppet> = this.ttPendingCorpse;
    let player: ref<PlayerPuppet> = this.ttPendingPlayer;
    let tier: Int32 = this.ttPendingTier;
    this.ttPendingCorpse = null;
    this.ttPendingPlayer = null;
    this.ttPendingTier = 0;
    this.ttPendingLocation = Vector4(0.0, 0.0, 0.0, 0.0);
    this.TTStartResponse(corpse, player, tier);
  };
}

@addMethod(PreventionSpawnSystem)
public final func TTRecordPassengers(vehicle: wref<VehicleObject>) -> Void {
  if IsDefined(this.ttResponse) { this.ttResponse.AttachPassengers(vehicle); };
}

@addMethod(PreventionSpawnSystem)
public final func TTIsResponder(npc: wref<NPCPuppet>) -> Bool {
  return IsDefined(this.ttResponse) && this.ttResponse.ContainsResponder(npc);
}

@addMethod(PreventionSpawnSystem)
public final func TTShouldHoldAV(vehicle: wref<VehicleObject>) -> Bool {
  return IsDefined(this.ttResponse) && this.ttResponse.ShouldHoldAV(vehicle);
}

@wrapMethod(PreventionSpawnSystem)
protected final func SpawnRequestFinished(requestResult: SpawnRequestResult) -> Void {
  wrappedMethod(requestResult);
  if IsDefined(this.ttResponse) { this.ttResponse.OnSpawn(requestResult); };
}
