// One active extraction at a time. Native prevention spawns supply the AV and NPCs.
public class WETraumaResponse extends IScriptable {
  public let system: wref<PreventionSpawnSystem>;
  public let corpse: wref<NPCPuppet>;
  public let player: wref<PlayerPuppet>;
  public let outdoors: Bool;
  public let tier: Int32;
  public let extraction: Vector4;
  private let avRequest: Uint32;
  private let truckRequest: Uint32;
  private let unitRequests: array<Uint32>;
  private let units: array<wref<NPCPuppet>>;
  private let medic: wref<NPCPuppet>;
  private let av: wref<VehicleObject>;
  private let truck: wref<VehicleObject>;
  private let entrySet: Bool;
  private let ticks: Int32;
  private let recovered: Bool;
  private let unitsRequested: Bool;
  private let medicRequest: Uint32;
  private let recoveryTick: Int32;
  private let extractionArrivalTick: Int32;
  private let crewClearedTick: Int32;
  private let finished: Bool;
  private let patientGroup: CName;
  private let patientEnemies: array<wref<NPCPuppet>>;
  private let blockedTicks: Int32;
  private let previousMedicDistance: Float;
  private let playerBlockedRecovery: Bool;
  private let secondsUntilArrival: Int32;

  public func TierName() -> String {
    if this.tier == 1 { return "SILVER"; };
    if this.tier == 2 { return "GOLD"; };
    return "PLATINUM";
  }

  public func ArrivalSeconds() -> Int32 {
    if this.tier == 1 { return 60; };
    if this.tier == 2 { return 45; };
    return 30;
  }

  public func BeginCountdown() -> Void {
    this.secondsUntilArrival = this.ArrivalSeconds();
    this.ScheduleCountdown();
  }

  public func CancelForSaveLoad() -> Void {
    if this.finished { return; };
    this.finished = true;
    if !IsDefined(this.system) { return; };
    for id in this.unitRequests { this.system.CancelSpawnRequest(id); };
    if this.avRequest != 0u && !IsDefined(this.av) { this.system.CancelSpawnRequest(this.avRequest); };
    if this.truckRequest != 0u && !IsDefined(this.truck) { this.system.CancelSpawnRequest(this.truckRequest); };
  }

  private func ScheduleCountdown() -> Void {
    if !IsDefined(this.player) { this.Finish(); return; };
    let callback: ref<WETraumaArrivalTick> = new WETraumaArrivalTick();
    callback.response = this;
    GameInstance.GetDelaySystem(this.player.GetGame()).DelayCallback(callback, 1.0, false);
  }

  public func CountdownTick() -> Void {
    if this.finished { return; };
    this.secondsUntilArrival -= 1;
    if this.secondsUntilArrival <= 0 { this.Start(); return; };
    if this.secondsUntilArrival % 5 == 0 {
      this.ShowMessage(s"TRAUMA TEAM \(this.TierName()): \(this.secondsUntilArrival)s ETA");
    };
    this.ScheduleCountdown();
  }

  public func Start() -> Void {
    if !IsDefined(this.corpse) || !IsDefined(this.system) { this.Finish(); return; };
    this.patientGroup = this.corpse.GetAttitudeAgent().GetAttitudeGroup();
    this.CapturePatientThreats(this.corpse);
    this.CaptureNearbyEnemies();
    if this.outdoors {
      // Wait for the AV before choosing the entry point or spawning the team.
      let avRecord: TweakDBID = this.tier == 1 ? t"Vehicle.TTTraumaSilverAV" : this.tier == 2 ? t"Vehicle.TTTraumaGoldAV" : t"Vehicle.TTTraumaResponseAV";
      this.avRequest = this.system.RequestAVSpawn(avRecord, Vector2(16.0, 30.0), true);
      ModLog(n"TraumaTeamSubscriptions", s"Waiting for AV request=\(this.avRequest)");
      if this.avRequest == 0u { this.RequestRoadTruck(); };
    } else {
      this.SpawnAtEntry(this.corpse.GetWorldPosition());
    };
    this.ScheduleTick();
  }

  private func RequestRoadTruck() -> Void {
    if this.truckRequest != 0u || IsDefined(this.truck) || this.unitsRequested { return; };
    let records: array<TweakDBID>;
    ArrayPush(records, t"Character.trauma_rare_officer_chao_ma");
    if this.tier >= 2 { ArrayPush(records, t"Character.trauma_rare_officer_chao_ma"); };
    if this.tier >= 3 { ArrayPush(records, t"Character.trauma_rare_officer_chao_ma"); };
    let strategy: ref<DriveTowardsPlayerStrategyRequest> = DriveTowardsPlayerStrategyRequest.Create(Vector2(45.0, 90.0), 12.0);
    let truckRecord: TweakDBID = this.tier == 1 ? t"Vehicle.TTTraumaSilverTruck" : this.tier == 2 ? t"Vehicle.TTTraumaGoldTruck" : t"Vehicle.TTTraumaRoadTruck";
    this.truckRequest = this.system.RequestChaseVehicle(truckRecord, records, strategy);
    if this.truckRequest == 0u {
      this.ShowMessage("TRAUMA TEAM: NO ROAD ACCESS");
      this.Finish();
    } else {
      this.ShowMessage("TRAUMA TEAM: ROAD RECOVERY EN ROUTE");
      ModLog(n"TraumaTeamSubscriptions", s"Militech road vehicle request=\(this.truckRequest)");
    };
  }

  private func FindEntry(anchor: Vector4, out point: Vector4) -> Bool {
    let nav: ref<AINavigationSystem> = GameInstance.GetAINavigationSystem(this.corpse.GetGame());
    let body: Vector4 = this.corpse.GetWorldPosition();
    let forward: Vector4 = this.corpse.GetWorldForward();
    let side: Vector4 = Vector4(-forward.Y, forward.X, 0.0, 0.0);
    let candidates: array<Vector4>;
    // Project the AV's horizontal position onto the body's floor. Search
    // further out if the AV is overhead or its landing zone is blocked.
    ArrayPush(candidates, Vector4(anchor.X, anchor.Y, body.Z, 1.0));
    ArrayPush(candidates, body + forward * 20.0);
    ArrayPush(candidates, body - forward * 20.0);
    ArrayPush(candidates, body + side * 20.0);
    ArrayPush(candidates, body - side * 20.0);
    for candidate in candidates {
      if Vector4.Distance(candidate, body) > 9.0 && nav.TryToFindNavmeshPointAroundPoint(this.corpse, candidate, this.corpse.GetWorldOrientation(), Vector4(1.0, 1.0, 2.0, 0.0), 12, 5.0, point, true) {
        if Vector4.Distance(point, body) > 8.0 { return true; };
      };
    };
    return false;
  }

  private func SpawnAtEntry(anchor: Vector4) -> Void {
    if this.unitsRequested { return; };
    let point: Vector4;
    if !this.FindEntry(anchor, point) {
      ModLog(n"TraumaTeamSubscriptions", "No distant reachable navmesh entry; cancelling recovery");
      this.ShowMessage("TRAUMA TEAM: NO SAFE LANDING ZONE");
      this.Finish();
      return;
    };
    this.unitsRequested = true;
    this.extraction = point;
    this.entrySet = true;
    let records: array<TweakDBID>;
    ArrayPush(records, t"Character.trauma_rare_officer_chao_ma");
    if this.tier >= 2 { ArrayPush(records, t"Character.trauma_rare_officer_chao_ma"); };
    if this.tier >= 3 { ArrayPush(records, t"Character.trauma_rare_officer_chao_ma"); };
    let transform: WorldTransform;
    let id: Uint32;
    WorldTransform.SetPosition(transform, point);
    for record in records {
      id = this.system.RequestUnitSpawn(record, transform);
      if id != 0u {
        if ArraySize(this.unitRequests) == 0 { this.medicRequest = id; };
        ArrayPush(this.unitRequests, id);
      };
    };
    ModLog(n"TraumaTeamSubscriptions", s"Team entering from \(point); responder requests=\(ArraySize(this.unitRequests))");
  }

  public func OnSpawn(result: SpawnRequestResult) -> Void {
    ModLog(n"TraumaTeamSubscriptions", s"Spawn request \(result.requestID) success=\(result.success) objects=\(ArraySize(result.spawnedObjects))");
    if result.requestID == this.avRequest && this.avRequest != 0u {
      for object in result.spawnedObjects {
        let vehicle: wref<VehicleObject> = object as VehicleObject;
        if IsDefined(vehicle) { this.av = vehicle; };
      };
      if IsDefined(this.av) {
        this.ShowMessage("TRAUMA TEAM AV ON SCENE");
        this.AttachPassengers(this.av);
      } else {
        ModLog(n"TraumaTeamSubscriptions", "AV unavailable; requesting Militech road recovery");
        this.avRequest = 0u;
        this.RequestRoadTruck();
      };
      return;
    };
    if result.requestID == this.truckRequest && this.truckRequest != 0u {
      for object in result.spawnedObjects {
        let vehicle: wref<VehicleObject> = object as VehicleObject;
        if IsDefined(vehicle) { this.truck = vehicle; };
      };
      if IsDefined(this.truck) {
        this.ShowMessage("TRAUMA TEAM ROAD UNIT ON SCENE");
        this.AttachPassengers(this.truck);
      } else {
        this.ShowMessage("TRAUMA TEAM: ROAD RECOVERY UNAVAILABLE");
        this.Finish();
      };
      return;
    };
    if !ArrayContains(this.unitRequests, result.requestID) { return; };
    let isMedic: Bool = result.requestID == this.medicRequest;
    ArrayRemove(this.unitRequests, result.requestID);
    if !result.success { return; };
    for object in result.spawnedObjects {
      let npc: wref<NPCPuppet> = object as NPCPuppet;
      if IsDefined(npc) {
        ArrayPush(this.units, npc);
        if isMedic {
          this.medic = npc;
        };
        GameObject.ChangeAttitudeToNeutral(npc, this.player);
        this.EngagePatientEnemies(npc);
        this.SendToCorpse(npc);
      };
    };
  }

  public func AttachPassengers(vehicle: wref<VehicleObject>) -> Void {
    if !IsDefined(vehicle) || this.finished { return; };
    if vehicle.GetRecordID() == t"Vehicle.TTTraumaResponseAV" || vehicle.GetRecordID() == t"Vehicle.TTTraumaSilverAV" || vehicle.GetRecordID() == t"Vehicle.TTTraumaGoldAV" { this.av = vehicle; };
    if vehicle.GetRecordID() == t"Vehicle.TTTraumaRoadTruck" || vehicle.GetRecordID() == t"Vehicle.TTTraumaSilverTruck" || vehicle.GetRecordID() == t"Vehicle.TTTraumaGoldTruck" { this.truck = vehicle; };
    let passengers: array<wref<GameObject>>;
    VehicleComponent.GetAllPassengers(vehicle.GetGame(), vehicle.GetEntityID(), false, passengers);
    for passenger in passengers {
      let npc: wref<NPCPuppet> = passenger as NPCPuppet;
      if IsDefined(npc) && !ArrayContains(this.units, npc) {
        ArrayPush(this.units, npc);
        this.unitsRequested = true;
        if !IsDefined(this.medic) { this.medic = npc; };
        GameObject.ChangeAttitudeToNeutral(npc, this.player);
        this.EngagePatientEnemies(npc);
      };
    };
    if ArraySize(this.units) > 0 && !this.entrySet {
      let point: Vector4;
      if this.FindEntry(vehicle.GetWorldPosition(), point) {
        this.extraction = point;
      } else {
        let vehiclePosition: Vector4 = vehicle.GetWorldPosition();
        let bodyPosition: Vector4 = this.corpse.GetWorldPosition();
        this.extraction = Vector4(vehiclePosition.X, vehiclePosition.Y, bodyPosition.Z, 1.0);
      };
      this.entrySet = true;
      ModLog(n"TraumaTeamSubscriptions", s"Attached \(ArraySize(this.units)) vehicle responders");
    };
  }

  public func ShouldHoldAV(vehicle: wref<VehicleObject>) -> Bool {
    return !this.finished && IsDefined(this.av) && IsDefined(vehicle) && this.av.GetEntityID() == vehicle.GetEntityID();
  }

  private func CapturePatientThreats(source: wref<NPCPuppet>) -> Void {
    if !IsDefined(source) { return; };
    let tracker: ref<TargetTrackerComponent> = source.GetTargetTrackerComponent();
    if !IsDefined(tracker) { return; };
    for threat in tracker.GetThreats(false) {
      let enemy: wref<NPCPuppet> = threat.entity as NPCPuppet;
      if IsDefined(enemy) && enemy != this.corpse && !ArrayContains(this.patientEnemies, enemy) && this.IsPatientEnemy(enemy) {
        ArrayPush(this.patientEnemies, enemy);
      };
    };
  }

  private func CaptureNearbyEnemies() -> Void {
    if !IsDefined(this.player) || !IsDefined(this.corpse) { return; };
    let query: TargetSearchQuery;
    let targets: array<TS_TargetPartInfo>;
    query.testedSet = TargetingSet.Complete;
    query.searchFilter = TSF_NPC();
    query.maxDistance = 45.0;
    query.filterObjectByDistance = true;
    query.includeSecondaryTargets = false;
    query.ignoreInstigator = true;
    GameInstance.GetTargetingSystem(this.player.GetGame()).GetTargetParts(this.player, query, targets);
    for target in targets {
      let part: wref<TargetingComponent> = TS_TargetPartInfo.GetComponent(target);
      if IsDefined(part) {
        let enemy: wref<NPCPuppet> = part.GetEntity() as NPCPuppet;
        if IsDefined(enemy) && !ArrayContains(this.patientEnemies, enemy) && this.IsPatientEnemy(enemy) {
          ArrayPush(this.patientEnemies, enemy);
        };
      };
    };
  }

  private func IsPatientEnemy(enemy: wref<NPCPuppet>) -> Bool {
    if !IsDefined(enemy) || !ScriptedPuppet.IsAlive(enemy) { return false; };
    if ArrayContains(this.units, enemy) { return false; };
    if Vector4.Distance(enemy.GetWorldPosition(), this.corpse.GetWorldPosition()) > 45.0 { return false; };
    let group: CName = enemy.GetAttitudeAgent().GetAttitudeGroup();
    let relation: EAIAttitude = GameInstance.GetAttitudeSystem(enemy.GetGame()).GetAttitudeRelation(this.patientGroup, group);
    return EnumInt(relation) == EnumInt(EAIAttitude.AIA_Hostile);
  }

  private func EngagePatientEnemies(responder: wref<NPCPuppet>) -> Void {
    if !IsDefined(responder) || responder == this.medic { return; };
    for enemy in this.patientEnemies {
      if this.IsPatientEnemy(enemy) && Vector4.Distance(enemy.GetWorldPosition(), responder.GetWorldPosition()) < 12.0 {
        GameObject.ChangeAttitudeToHostile(responder, enemy);
        TargetTrackingExtension.InjectThreat(responder, enemy, 1.0, -1.0);
      };
    };
  }

  private func CheckBlockedMedic() -> Void {
    if this.playerBlockedRecovery || this.recovered || !IsDefined(this.medic) || !IsDefined(this.corpse) { return; };
    let distance: Float = Vector4.Distance(this.medic.GetWorldPosition(), this.corpse.GetWorldPosition());
    if distance > 4.0 && Vector4.Distance(this.player.GetWorldPosition(), this.medic.GetWorldPosition()) < 1.8 && AbsF(distance - this.previousMedicDistance) < 0.25 {
      this.blockedTicks += 1;
    } else {
      this.blockedTicks = 0;
    };
    this.previousMedicDistance = distance;
    if this.blockedTicks >= 4 {
      this.playerBlockedRecovery = true;
      for responder in this.units {
        if IsDefined(responder) && responder != this.medic {
          GameObject.ChangeAttitudeToHostile(responder, this.player);
          TargetTrackingExtension.InjectThreat(responder, this.player, 1.0, -1.0);
        };
      };
    };
  }

  private func SendToCorpse(npc: wref<NPCPuppet>) -> Void {
    if !IsDefined(npc) || !IsDefined(this.corpse) { return; };
    if VehicleComponent.IsMountedToVehicle(npc.GetGame(), npc) { return; };
    let command: ref<AIMoveToCommand> = new AIMoveToCommand();
    let position: WorldPosition;
    WorldPosition.SetVector4(position, this.corpse.GetWorldPosition());
    AIPositionSpec.SetWorldPosition(command.movementTarget, position);
    command.desiredDistanceFromTarget = 2.0;
    command.movementType = moveMovementType.Sprint;
    command.finishWhenDestinationReached = true;
    npc.GetAIControllerComponent().SendCommand(command);
  }

  private func SendToEntry(npc: wref<NPCPuppet>) -> Void {
    if !IsDefined(npc) { return; };
    let retreat: ref<AIMoveToCommand> = new AIMoveToCommand();
    let entryPosition: WorldPosition;
    WorldPosition.SetVector4(entryPosition, this.extraction);
    AIPositionSpec.SetWorldPosition(retreat.movementTarget, entryPosition);
    retreat.desiredDistanceFromTarget = 2.0;
    retreat.movementType = moveMovementType.Sprint;
    retreat.finishWhenDestinationReached = true;
    npc.GetAIControllerComponent().SendCommand(retreat);
  }

  private func HoldAtEntry() -> Void {
    for npc in this.units {
      if IsDefined(npc) && ScriptedPuppet.IsAlive(npc) {
        let hold: ref<AIHoldPositionCommand> = new AIHoldPositionCommand();
        hold.duration = 8.0;
        AIComponent.SendCommand(npc, hold);
      };
    };
  }

  private func ClearCrew() -> Void {
    if !IsDefined(this.system) { return; };
    for npc in this.units {
      if IsDefined(npc) {
        npc.HideIrreversibly();
        this.system.RequestDespawn(npc.GetEntityID());
      };
    };
  }

  private func ShowMessage(text: String) -> Void {
    if !IsDefined(this.player) { return; };
    let message: SimpleScreenMessage;
    let notifications = GetAllBlackboardDefs().UI_Notifications;
    message.message = text;
    message.isShown = true;
    message.duration = 3.0;
    GameInstance.GetBlackboardSystem(this.player.GetGame()).Get(notifications).SetVariant(notifications.OnscreenMessage, ToVariant(message), true);
  }

  private func ScheduleTick() -> Void {
    if !IsDefined(this.system) || !IsDefined(this.player) { return; };
    let callback: ref<WETraumaTick> = new WETraumaTick();
    callback.response = this;
    GameInstance.GetDelaySystem(this.player.GetGame()).DelayCallback(callback, 1.0, false);
  }

  public func Tick() -> Void {
    if this.finished { return; };
    this.ticks += 1;
    if !IsDefined(this.system) || !IsDefined(this.player) || this.ticks > 90 {
      ModLog(n"TraumaTeamSubscriptions", "Response timed out or lost player/system");
      this.Finish(); return;
    };
    if IsDefined(this.av) { this.AttachPassengers(this.av); };
    if IsDefined(this.truck) { this.AttachPassengers(this.truck); };
    if IsDefined(this.medic) && !ScriptedPuppet.IsAlive(this.medic) {
      ModLog(n"TraumaTeamSubscriptions", "Recovery medic killed; AV aborting without crew");
      this.Finish(); return;
    };
    if !this.unitsRequested && !IsDefined(this.av) && this.truckRequest == 0u && this.ticks > 25 {
      ModLog(n"TraumaTeamSubscriptions", "AV callback timed out; requesting road recovery");
      if this.avRequest != 0u {
        this.system.CancelSpawnRequest(this.avRequest);
        this.avRequest = 0u;
      };
      this.RequestRoadTruck();
    };
    if !this.recovered && IsDefined(this.corpse) && IsDefined(this.medic) {
      this.CheckBlockedMedic();
      if this.ticks % 8 == 0 && Vector4.Distance(this.medic.GetWorldPosition(), this.corpse.GetWorldPosition()) > 4.0 {
        this.SendToCorpse(this.medic);
      };
      if Vector4.Distance(this.medic.GetWorldPosition(), this.corpse.GetWorldPosition()) < 3.0 {
        this.recovered = true;
        this.recoveryTick = this.ticks;
        ModLog(n"TraumaTeamSubscriptions", "Medic reached corpse; simulating pickup");
        // Use the game's body-disposal event. Iterating a dead puppet's visual
        // components caused repeatable native access violations.
        let hide: ref<HidePuppetDelayEvent> = new HidePuppetDelayEvent();
        hide.m_target = this.corpse;
        this.corpse.QueueEvent(hide);
        for npc in this.units { this.SendToEntry(npc); };
      };
    };
    if this.extractionArrivalTick == 0 && this.ticks % 4 == 0 {
      this.CapturePatientThreats(this.corpse);
      this.CapturePatientThreats(this.medic);
      this.CaptureNearbyEnemies();
      for responder in this.units {
        this.CapturePatientThreats(responder);
        this.EngagePatientEnemies(responder);
      };
    };
    if this.extractionArrivalTick == 0 && this.ticks % 2 == 0 {
      for responder in this.units {
        if this.recovered { this.SendToEntry(responder); }
        else { this.SendToCorpse(responder); };
      };
    };
    if this.recovered && this.extractionArrivalTick == 0 && IsDefined(this.medic) && this.ticks > this.recoveryTick + 3 && Vector4.Distance(this.medic.GetWorldPosition(), this.extraction) < 4.0 {
      let teamAtExtraction: Bool = true;
      for responder in this.units {
        if IsDefined(responder) && ScriptedPuppet.IsAlive(responder) && Vector4.Distance(responder.GetWorldPosition(), this.extraction) > 6.0 {
          teamAtExtraction = false;
        };
      };
      if teamAtExtraction || this.ticks > this.recoveryTick + 25 {
        this.extractionArrivalTick = this.ticks;
        this.HoldAtEntry();
        ModLog(n"TraumaTeamSubscriptions", "Recovery squad at extraction; holding AV for five seconds");
      };
    };
    if this.extractionArrivalTick > 0 && this.crewClearedTick == 0 && this.ticks >= this.extractionArrivalTick + 5 {
      this.ClearCrew();
      this.crewClearedTick = this.ticks;
      this.ShowMessage("TRAUMA TEAM: PATIENT EXTRACTED");
      ModLog(n"TraumaTeamSubscriptions", "Crew cleared; releasing AV on next tick");
    };
    if this.crewClearedTick > 0 && this.ticks > this.crewClearedTick {
      this.Finish(); return;
    };
    this.ScheduleTick();
  }

  private func Finish() -> Void {
    if this.finished { return; };
    this.finished = true;
    if IsDefined(this.system) {
      for id in this.unitRequests { this.system.CancelSpawnRequest(id); };
      if this.avRequest != 0u && !IsDefined(this.av) { this.system.CancelSpawnRequest(this.avRequest); };
      if this.truckRequest != 0u && !IsDefined(this.truck) { this.system.CancelSpawnRequest(this.truckRequest); };
      // The old cleanup also despawned the AV with its passengers and crashed.
      // Normal extraction has already hidden the crew one tick before the AV
      // is released. On a timeout, request ordinary cleanup without hiding.
      if this.crewClearedTick == 0 {
        for npc in this.units {
          if IsDefined(npc) { this.system.RequestDespawn(npc.GetEntityID()); };
        };
      };
      this.system.TTFinishResponse(this);
    };
  }
}

public class WETraumaTick extends DelayCallback {
  public let response: ref<WETraumaResponse>;
  public func Call() -> Void {
    if IsDefined(this.response) { this.response.Tick(); };
  }
}

public class WETraumaArrivalTick extends DelayCallback {
  public let response: ref<WETraumaResponse>;
  public func Call() -> Void {
    if IsDefined(this.response) { this.response.CountdownTick(); };
  }
}
