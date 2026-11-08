@addField(PreventionSpawnSystem)
private let ttResponse: ref<WETraumaResponse>;

@addField(PreventionSpawnSystem)
private let ttPendingCorpse: ref<NPCPuppet>;

@addField(PreventionSpawnSystem)
private let ttPendingPlayer: ref<PlayerPuppet>;

@addField(PreventionSpawnSystem)
private let ttPendingTier: Int32;

@addMethod(PreventionSpawnSystem)
public final func TTResetForSaveLoad() -> Void {
  let response: ref<WETraumaResponse> = this.ttResponse;
  this.ttResponse = null;
  this.ttPendingCorpse = null;
  this.ttPendingPlayer = null;
  this.ttPendingTier = 0;
  if IsDefined(response) { response.CancelForSaveLoad(); };
  ModLog(n"TraumaTeamSubscriptions", "Cleared dispatch state for save load");
}

@addMethod(PreventionSpawnSystem)
public final func TTStartResponse(corpse: ref<NPCPuppet>, player: ref<PlayerPuppet>, tier: Int32) -> Bool {
  if !IsDefined(corpse) || !IsDefined(player) { return false; };
  // One live recovery and one waiting dispatch at most, globally.
  if IsDefined(this.ttResponse) {
    if IsDefined(this.ttPendingCorpse) { return false; };
    this.ttPendingCorpse = corpse;
    this.ttPendingPlayer = player;
    this.ttPendingTier = tier;
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
  if IsDefined(this.ttPendingCorpse) {
    let corpse: ref<NPCPuppet> = this.ttPendingCorpse;
    let player: ref<PlayerPuppet> = this.ttPendingPlayer;
    let tier: Int32 = this.ttPendingTier;
    this.ttPendingCorpse = null;
    this.ttPendingPlayer = null;
    this.ttPendingTier = 0;
    this.TTStartResponse(corpse, player, tier);
  };
}

@addMethod(PreventionSpawnSystem)
public final func TTRecordPassengers(vehicle: wref<VehicleObject>) -> Void {
  if IsDefined(this.ttResponse) { this.ttResponse.AttachPassengers(vehicle); };
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
