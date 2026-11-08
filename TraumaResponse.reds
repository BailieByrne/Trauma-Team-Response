// One active extraction at a time. Native prevention spawns supply the AV and NPCs.
public class WETraumaResponse extends IScriptable {
  public let system: wref<PreventionSpawnSystem>;
  public let corpse: wref<NPCPuppet>;
  public let player: wref<PlayerPuppet>;
  public let outdoors: Bool;
  public let tier: Int32;
  public let extraction: Vector4;
  public let incidentPosition: Vector4;
  private let avRequest: Uint32;
  private let truckRequest: Uint32;
  private let unitRequests: array<Uint32>;
  private let units: array<wref<NPCPuppet>>;
  private let patientOrders: array<wref<NPCPuppet>>;
  private let retreatOrders: array<wref<NPCPuppet>>;
  private let avRetreatRetried: array<wref<NPCPuppet>>;
  private let boardOrders: array<wref<NPCPuppet>>;
  private let medic: wref<NPCPuppet>;
  private let av: wref<VehicleObject>;
  private let truck: wref<VehicleObject>;
  private let roadStopTicks: Int32;
  private let roadExitTick: Int32;
  private let roadExitForced: Bool;
  private let roadBoardingTick: Int32;
  private let roadDepartTick: Int32;
  private let roadCleanupTick: Int32;
  private let roadSeatFixRequested: Bool;
  private let roadTruckSeen: Bool;
  private let replacementUsed: Bool;
  private let replacementEvac: Bool;
  private let replacementArrivalTick: Int32;
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
  private let previousRouteDistance: Float;
  private let medicStallTicks: Int32;
  private let previousRetreatDistance: Float;
  private let retreatStallTicks: Int32;
  private let playerBlockedRecovery: Bool;
  private let secondsUntilArrival: Int32;

  public func TierName() -> String {
    if this.tier == 1 { return "SILVER"; };
    if this.tier == 2 { return "GOLD"; };
    return "PLATINUM";
  }

  public func ArrivalSeconds() -> Int32 {
    let config: ref<TraumaTeamConfig> = this.system.TTGetConfig();
    if this.tier == 1 { return config.silverDelay; };
    if this.tier == 2 { return config.goldDelay; };
    return config.platinumDelay;
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
    if IsDefined(this.system) { this.system.TTPrunePendingResponse(); };
    if !this.PatientStillNearby() {
      this.CancelAbandoned();
      return;
    };
    this.secondsUntilArrival -= 1;
    if this.secondsUntilArrival <= 0 { this.Start(); return; };
    if this.secondsUntilArrival % 5 == 0 {
      this.ShowMessage(s"TRAUMA TEAM \(this.TierName()): \(this.secondsUntilArrival)s ETA");
    };
    this.ScheduleCountdown();
  }

  public func Start() -> Void {
    if !this.PatientStillNearby() { this.CancelAbandoned(); return; };
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
    if !this.replacementEvac {
      if this.tier >= 2 { ArrayPush(records, t"Character.trauma_rare_officer_chao_ma"); };
      if this.tier >= 3 { ArrayPush(records, t"Character.trauma_rare_officer_chao_ma"); };
    };
    // Spawn on a nearby road so the truck reaches the patient shortly after
    // the dispatch countdown, rather than driving in from another block.
    let strategy: ref<DriveTowardsPlayerStrategyRequest> = DriveTowardsPlayerStrategyRequest.Create(Vector2(20.0, 40.0), 10.0);
    let truckRecord: TweakDBID = this.tier == 1 ? t"Vehicle.TTTraumaSilverTruck" : this.tier == 2 ? t"Vehicle.TTTraumaGoldTruck" : t"Vehicle.TTTraumaRoadTruck";
    this.truckRequest = this.system.RequestChaseVehicle(truckRecord, records, strategy);
    if this.truckRequest == 0u {
      this.FallBackOnFoot();
    } else {
      this.ShowMessage("TRAUMA TEAM: ROAD RECOVERY EN ROUTE");
      ModLog(n"TraumaTeamSubscriptions", s"Militech road vehicle request=\(this.truckRequest)");
    };
  }

  // Dispatch priority is AV, then road crew, then a team on foot.
  private func FallBackOnFoot() -> Void {
    if this.replacementUsed || !IsDefined(this.corpse) {
      this.ShowMessage("Rescue Failed Cyber Psycho Coverage Not Included");
      this.Finish();
      return;
    };
    this.ShowMessage("TRAUMA TEAM: NO VEHICLE ACCESS, RESPONDERS ON FOOT");
    ModLog(n"TraumaTeamSubscriptions", "No AV or road vehicle available; dispatching on foot");
    this.SpawnAtEntry(this.corpse.GetWorldPosition());
  }

  // If the AV turns up after a road truck was already requested, the AV wins:
  // stand the truck crew down and let the AV carry the recovery.
  private func PreferAV() -> Void {
    if this.recovered || this.replacementUsed || this.roadDepartTick > 0 || !IsDefined(this.system) { return; };
    if this.truckRequest == 0u && !IsDefined(this.truck) { return; };
    ModLog(n"TraumaTeamSubscriptions", "AV arrived after road request; standing road crew down");
    if !IsDefined(this.truck) { this.system.CancelSpawnRequest(this.truckRequest); };
    this.ClearCrew();
    if IsDefined(this.truck) && IsDefined(this.player) {
      // Crew first, vehicle a moment later; never despawn both together.
      let later: ref<WETraumaDespawnCallback> = new WETraumaDespawnCallback();
      later.system = this.system;
      later.target = this.truck.GetEntityID();
      GameInstance.GetDelaySystem(this.player.GetGame()).DelayCallback(later, 2.0, false);
    };
    ArrayClear(this.units);
    ArrayClear(this.patientOrders);
    ArrayClear(this.retreatOrders);
    ArrayClear(this.boardOrders);
    this.medic = null;
    this.truck = null;
    this.truckRequest = 0u;
    this.roadTruckSeen = false;
    this.unitsRequested = false;
    this.entrySet = false;
    this.roadStopTicks = 0;
    this.roadExitTick = 0;
    this.roadExitForced = false;
    this.roadBoardingTick = 0;
    this.roadSeatFixRequested = false;
  }

  // Settle detection for the AV medic. previousRetreatDistance (last height)
  // and retreatStallTicks (stationary ticks) are only used after pickup, so
  // they are borrowed here rather than adding fields to the saved class. Both
  // are reset when the medic reaches the patient.
  private func TrackAVLanding() -> Void {
    if this.recovered || this.entrySet || !IsDefined(this.av) || !IsDefined(this.medic) { return; };
    if VehicleComponent.IsMountedToVehicle(this.medic.GetGame(), this.medic) {
      this.retreatStallTicks = 0;
      this.previousRetreatDistance = 0.0;
      return;
    };
    let height: Float = this.medic.GetWorldPosition().Z;
    if AbsF(height - this.previousRetreatDistance) < 0.3 { this.retreatStallTicks += 1; }
    else { this.retreatStallTicks = 0; };
    this.previousRetreatDistance = height;
  }

  // Close enough counts as picked up. Dead bodies often sit on the navmesh
  // edge or among props, so the medic can finish its run a few metres short.
  private func MedicAtPatient() -> Bool {
    if !IsDefined(this.medic) || !IsDefined(this.corpse) { return false; };
    if VehicleComponent.IsMountedToVehicle(this.medic.GetGame(), this.medic) { return false; };
    if IsDefined(this.av) && !this.entrySet { return false; };
    let medicPosition: Vector4 = this.medic.GetWorldPosition();
    let bodyPosition: Vector4 = this.corpse.GetWorldPosition();
    let flat: Float = Vector4.Distance2D(medicPosition, bodyPosition);
    let height: Float = AbsF(medicPosition.Z - bodyPosition.Z);
    if flat <= 2.0 && height <= 2.5 { return true; };
    if flat <= 5.0 && height <= 3.0 && this.medicStallTicks >= 2 && ArrayContains(this.patientOrders, this.medic) { return true; };
    return false;
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
    if result.requestID != this.avRequest && result.requestID != this.truckRequest && !ArrayContains(this.unitRequests, result.requestID) { return; };
    ModLog(n"TraumaTeamSubscriptions", s"Spawn request \(result.requestID) success=\(result.success) objects=\(ArraySize(result.spawnedObjects))");
    if result.requestID == this.avRequest && this.avRequest != 0u {
      let foundAV: wref<VehicleObject>;
      for object in result.spawnedObjects {
        let vehicle: wref<VehicleObject> = object as VehicleObject;
        if IsDefined(vehicle) { foundAV = vehicle; };
      };
      if IsDefined(foundAV) {
        this.PreferAV();
        this.av = foundAV;
        this.ShowMessage("TRAUMA TEAM AV ON SCENE");
        this.AttachPassengers(foundAV);
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
        this.roadTruckSeen = true;
        this.AttachPassengers(this.truck);
      } else {
        this.truckRequest = 0u;
        this.FallBackOnFoot();
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
        if !this.recovered { this.EngagePatientEnemies(npc); };
        this.SendToCorpse(npc);
      };
    };
  }

  public func AttachPassengers(vehicle: wref<VehicleObject>) -> Void {
    if !IsDefined(vehicle) || this.finished { return; };
    if vehicle.GetRecordID() == t"Vehicle.TTTraumaResponseAV" || vehicle.GetRecordID() == t"Vehicle.TTTraumaSilverAV" || vehicle.GetRecordID() == t"Vehicle.TTTraumaGoldAV" {
      if !IsDefined(this.av) { this.PreferAV(); };
      this.av = vehicle;
    };
    if vehicle.GetRecordID() == t"Vehicle.TTTraumaRoadTruck" || vehicle.GetRecordID() == t"Vehicle.TTTraumaSilverTruck" || vehicle.GetRecordID() == t"Vehicle.TTTraumaGoldTruck" {
      this.truck = vehicle;
      this.roadTruckSeen = true;
    };
    let passengers: array<wref<GameObject>>;
    VehicleComponent.GetAllPassengers(vehicle.GetGame(), vehicle.GetEntityID(), false, passengers);
    for passenger in passengers {
      let npc: wref<NPCPuppet> = passenger as NPCPuppet;
      if IsDefined(npc) && !ArrayContains(this.units, npc) {
        ArrayPush(this.units, npc);
        this.unitsRequested = true;
        if !IsDefined(this.medic) { this.medic = npc; };
        GameObject.ChangeAttitudeToNeutral(npc, this.player);
        if !this.recovered { this.EngagePatientEnemies(npc); };
      };
    };
    // Vehicle spawn positions are not extraction points. The AV's ground
    // destination is captured at dismount; the truck's when it parks.
  }

  private func ReleaseRoadCrew() -> Void {
    if !IsDefined(this.truck) || !IsDefined(this.corpse) || this.recovered || ArraySize(this.units) == 0 { return; };
    // The chase truck has no MaxTac AV dismount script. Wait until it has
    // stopped near the patient, then ask each passenger to exit normally.
    if AbsF(this.truck.GetCurrentSpeed()) > 1.5 || Vector4.Distance(this.truck.GetWorldPosition(), this.corpse.GetWorldPosition()) > 100.0 {
      this.roadStopTicks = 0;
      return;
    };
    this.roadStopTicks += 1;
    if this.roadStopTicks < 2 { return; };
    if !this.entrySet {
      let truckPosition: Vector4 = this.truck.GetWorldPosition();
      let bodyPosition: Vector4 = this.corpse.GetWorldPosition();
      let nav: ref<AINavigationSystem> = GameInstance.GetAINavigationSystem(this.corpse.GetGame());
      let point: Vector4;
      if nav.TryToFindNavmeshPointAroundPoint(this.corpse, truckPosition, this.corpse.GetWorldOrientation(), Vector4(1.0, 1.0, 2.0, 0.0), 12, 5.0, point, true) {
        this.extraction = point;
      } else {
        this.extraction = Vector4(truckPosition.X, truckPosition.Y, bodyPosition.Z, 1.0);
      };
      this.entrySet = true;
      this.ShowMessage("TRAUMA TEAM ROAD UNIT ON SCENE");
      ModLog(n"TraumaTeamSubscriptions", s"Road unit stopped at \(this.extraction)");
    };
    if this.roadExitTick == 0 {
      this.roadExitTick = this.ticks;
      for npc in this.units {
        if IsDefined(npc) && VehicleComponent.IsMountedToVehicle(npc.GetGame(), npc) {
          npc.QueueEvent(AIEvents.ExitVehicleEvent());
        };
      };
      ModLog(n"TraumaTeamSubscriptions", s"Road unit stopped; ordered \(ArraySize(this.units)) responders out");
      return;
    };
    // Some prevention passenger AI ignores ExitVehicle. Use the same workspot
    // unmount call as the game's vehicle exit task if they are still seated.
    if !this.roadExitForced && this.ticks >= this.roadExitTick + 5 {
      this.roadExitForced = true;
      for npc in this.units {
        if IsDefined(npc) && VehicleComponent.IsMountedToVehicle(npc.GetGame(), npc) {
          GameInstance.GetWorkspotSystem(npc.GetGame()).UnmountFromVehicle(this.truck, npc, false);
        };
      };
      ModLog(n"TraumaTeamSubscriptions", "Road unit exit fallback requested");
    };
    if this.roadExitForced && this.ticks == this.roadExitTick + 12 {
      for npc in this.units {
        if IsDefined(npc) && VehicleComponent.IsMountedToVehicle(npc.GetGame(), npc) {
          GameInstance.GetWorkspotSystem(npc.GetGame()).UnmountFromVehicle(this.truck, npc, true);
        };
      };
      ModLog(n"TraumaTeamSubscriptions", "Road unit forced exit after failed animated dismount");
    };
  }

  private func HandleRoadLoss() -> Void {
    if this.roadDepartTick > 0 { return; };
    if this.tier < 3 || this.replacementUsed {
      this.ShowMessage("Rescue Failed Cyber Psycho Coverage Not Included");
      ModLog(n"TraumaTeamSubscriptions", "Road recovery failed; no further coverage");
      this.Finish();
      return;
    };
    this.replacementUsed = true;
    this.replacementEvac = this.recovered;
    this.ShowMessage("TRAUMA TEAM PLATINUM: REPLACEMENT UNIT EN ROUTE");
    ModLog(n"TraumaTeamSubscriptions", s"Platinum replacement requested; patient recovered=\(this.recovered)");
    // Leave an intact first truck to the game's normal cleanup while its
    // passengers dismount. Despawning a mounted crew and vehicle together
    // caused a native crash in an earlier recovery build.
    if IsDefined(this.truck) && this.truck.IsDestroyed() {
      this.system.RequestDespawn(this.truck.GetEntityID());
    };
    if !this.recovered {
      this.ClearCrew();
      ArrayClear(this.units);
    } else {
      let survivors: array<wref<NPCPuppet>>;
      for npc in this.units {
        if IsDefined(npc) && ScriptedPuppet.IsAlive(npc) {
          if IsDefined(this.truck) && VehicleComponent.IsMountedToVehicle(npc.GetGame(), npc) {
            GameInstance.GetWorkspotSystem(npc.GetGame()).UnmountFromVehicle(this.truck, npc, true);
          };
          ArrayPush(survivors, npc);
        };
      };
      ArrayClear(this.units);
      for survivor in survivors { ArrayPush(this.units, survivor); };
    };
    this.medic = null;
    ArrayClear(this.patientOrders);
    ArrayClear(this.retreatOrders);
    ArrayClear(this.boardOrders);
    this.truck = null;
    this.truckRequest = 0u;
    this.roadTruckSeen = false;
    this.unitsRequested = false;
    this.entrySet = false;
    this.roadStopTicks = 0;
    this.roadExitTick = 0;
    this.roadExitForced = false;
    this.roadBoardingTick = 0;
    this.roadDepartTick = 0;
    this.roadCleanupTick = 0;
    this.roadSeatFixRequested = false;
    this.extractionArrivalTick = 0;
    this.replacementArrivalTick = 0;
    this.RequestRoadTruck();
  }

  private func TickReplacementEvac() -> Void {
    if !IsDefined(this.truck) || !IsDefined(this.corpse) { return; };
    if AbsF(this.truck.GetCurrentSpeed()) > 1.5 || Vector4.Distance(this.truck.GetWorldPosition(), this.corpse.GetWorldPosition()) > 100.0 { return; };
    if this.replacementArrivalTick == 0 {
      this.replacementArrivalTick = this.ticks;
      let truckPosition: Vector4 = this.truck.GetWorldPosition();
      let bodyPosition: Vector4 = this.corpse.GetWorldPosition();
      this.extraction = Vector4(truckPosition.X, truckPosition.Y, bodyPosition.Z, 1.0);
      this.entrySet = true;
      this.ShowMessage("TRAUMA TEAM: REPLACEMENT EVAC ON SCENE");
      ModLog(n"TraumaTeamSubscriptions", "Replacement truck stopped for surviving crew");
    };
    let crewNearTruck: Bool = true;
    for npc in this.units {
      if IsDefined(npc) && ScriptedPuppet.IsAlive(npc) && !VehicleComponent.IsMountedToVehicle(npc.GetGame(), npc) {
        this.SendToEntry(npc);
        if Vector4.Distance2D(npc.GetWorldPosition(), this.truck.GetWorldPosition()) > 7.0 { crewNearTruck = false; };
      };
    };
    if this.roadBoardingTick == 0 && (crewNearTruck || this.ticks >= this.replacementArrivalTick + 15) {
      this.extractionArrivalTick = this.ticks;
      this.BeginRoadBoarding();
    };
  }

  public func ShouldHoldAV(vehicle: wref<VehicleObject>) -> Bool {
    return !this.finished && IsDefined(this.av) && IsDefined(vehicle) && this.av.GetEntityID() == vehicle.GetEntityID();
  }

  public func ContainsResponder(npc: wref<NPCPuppet>) -> Bool {
    return IsDefined(npc) && ArrayContains(this.units, npc);
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
    if VehicleComponent.IsMountedToVehicle(this.medic.GetGame(), this.medic) { return; };
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
    // The actual dismount point is the only reliable return destination for
    // a prevention AV. Its spawn position is airborne and can change before
    // pickup. Capture the medic's landing before ordering anyone to move.
    if IsDefined(this.av) && !this.entrySet {
      // Still dropping from the AV. Ordering a run (or recording the return
      // point) mid-fall restarts the locomotion on landing and looks like a
      // stutter, so wait until the medic has stood still on the ground.
      if this.retreatStallTicks < 1 { return; };
      if npc == this.medic {
        this.extraction = npc.GetWorldPosition();
        this.entrySet = true;
        ModLog(n"TraumaTeamSubscriptions", s"AV medic landed at extraction \(this.extraction)");
      };
    };
    if ArrayContains(this.patientOrders, npc) { return; };
    let desiredDistance: Float = npc == this.medic ? 0.7 : 2.5;
    if Vector4.Distance2D(npc.GetWorldPosition(), this.corpse.GetWorldPosition()) <= desiredDistance { return; };
    let command: ref<AIMoveToCommand> = new AIMoveToCommand();
    let position: WorldPosition;
    WorldPosition.SetVector4(position, this.corpse.GetWorldPosition());
    AIPositionSpec.SetWorldPosition(command.movementTarget, position);
    command.desiredDistanceFromTarget = desiredDistance;
    command.movementType = moveMovementType.Sprint;
    command.finishWhenDestinationReached = true;
    npc.GetAIControllerComponent().SendCommand(command);
    ArrayPush(this.patientOrders, npc);
  }

  private func SendToEntry(npc: wref<NPCPuppet>) -> Void {
    if !IsDefined(npc) { return; };
    if VehicleComponent.IsMountedToVehicle(npc.GetGame(), npc) || ArrayContains(this.retreatOrders, npc) { return; };
    if IsDefined(this.truck) && Vector4.Distance2D(npc.GetWorldPosition(), this.truck.GetWorldPosition()) <= 7.0 { return; };
    let retreat: ref<AIMoveToCommand> = new AIMoveToCommand();
    let entryPosition: WorldPosition;
    WorldPosition.SetVector4(entryPosition, this.extraction);
    AIPositionSpec.SetWorldPosition(retreat.movementTarget, entryPosition);
    retreat.desiredDistanceFromTarget = IsDefined(this.truck) ? 1.5 : 2.0;
    retreat.movementType = moveMovementType.Sprint;
    retreat.finishWhenDestinationReached = true;
    npc.GetAIControllerComponent().SendCommand(retreat);
    ArrayPush(this.retreatOrders, npc);
  }

  private func HoldAtEntry() -> Void {
    for npc in this.units {
      if IsDefined(npc) && ScriptedPuppet.IsAlive(npc) {
        let hold: ref<AIHoldPositionCommand> = new AIHoldPositionCommand();
        hold.duration = 3.0;
        AIComponent.SendCommand(npc, hold);
      };
    };
  }

  private func BeginRoadBoarding() -> Void {
    if !IsDefined(this.truck) || this.roadBoardingTick > 0 { return; };
    this.roadBoardingTick = this.ticks;
    this.TickRoadBoarding();
    ModLog(n"TraumaTeamSubscriptions", "Road squad reached truck; boarding nearby responders");
  }

  private func TickRoadBoarding() -> Void {
    if !IsDefined(this.truck) { return; };
    for npc in this.units {
      if IsDefined(npc) && ScriptedPuppet.IsAlive(npc) && !VehicleComponent.IsMountedToVehicle(npc.GetGame(), npc) && !ArrayContains(this.boardOrders, npc) && Vector4.Distance2D(npc.GetWorldPosition(), this.truck.GetWorldPosition()) <= 7.0 {
        let preferred: CName = npc == this.medic ? n"seat_front_left" : n"first_available";
        let slot: CName = this.truck.GetAIComponent().TryReserveSeatOrFirstAvailable(npc.GetEntityID(), preferred);
        if IsNameValid(slot) {
          let mountData: ref<MountEventData> = new MountEventData();
          mountData.slotName = slot;
          mountData.mountParentEntityId = this.truck.GetEntityID();
          // The responder is already beside the truck. Let the game's
          // normal vehicle entry animation finish the single mount order.
          mountData.isInstant = false;
          mountData.ignoreHLS = true;
          let command: ref<AIMountCommand> = new AIMountCommand();
          command.mountData = mountData;
          let event: ref<AICommandEvent> = new AICommandEvent();
          event.command = command;
          npc.QueueEvent(event);
          ArrayPush(this.boardOrders, npc);
          ModLog(n"TraumaTeamSubscriptions", s"Road responder boarding at truck position \(this.truck.GetWorldPosition())");
        };
      };
    };
  }

  private func TickRoadDeparture() -> Void {
    if this.roadBoardingTick == 0 || !IsDefined(this.truck) { return; };
    this.TickRoadBoarding();
    if !this.roadSeatFixRequested && this.ticks >= this.roadBoardingTick + 5 {
      this.roadSeatFixRequested = true;
      let driver: wref<GameObject> = VehicleComponent.GetDriver(this.truck.GetGame(), this.truck, this.truck.GetEntityID());
      if !IsDefined(driver) && IsDefined(this.medic) && VehicleComponent.IsMountedToVehicle(this.medic.GetGame(), this.medic) {
        GameInstance.GetWorkspotSystem(this.truck.GetGame()).SwitchSeatVehicle(this.truck, this.medic, n"OccupantSlots", n"seat_front_left");
        ModLog(n"TraumaTeamSubscriptions", "Road medic moving to driver seat");
      };
    };
    if this.roadDepartTick == 0 && this.ticks >= this.roadBoardingTick + 8 {
      let allAboard: Bool = true;
      for npc in this.units {
        if IsDefined(npc) && ScriptedPuppet.IsAlive(npc) && !VehicleComponent.IsMountedToVehicle(npc.GetGame(), npc) { allAboard = false; };
      };
      if !allAboard && this.ticks < this.roadBoardingTick + 25 { return; };
      let driver: wref<GameObject> = VehicleComponent.GetDriver(this.truck.GetGame(), this.truck, this.truck.GetEntityID());
      for npc in this.units {
        if IsDefined(npc) && !VehicleComponent.IsMountedToVehicle(npc.GetGame(), npc) {
          npc.HideIrreversibly();
          this.system.RequestDespawn(npc.GetEntityID());
        };
      };
      // The native panic drive command is the game's flee behavior. Send it
      // even when GetDriver is late to recognize the newly boarded medic.
      let drive: ref<AIVehiclePanicCommand> = new AIVehiclePanicCommand();
      drive.allowSimplifiedMovement = true;
      drive.ignoreTickets = true;
      drive.useSpeedBasedLookupRange = true;
      drive.tryDriveAwayFromPlayer = true;
      let event: ref<AICommandEvent> = new AICommandEvent();
      event.command = drive;
      this.truck.QueueEvent(event);
      this.roadDepartTick = this.ticks;
      ModLog(n"TraumaTeamSubscriptions", s"Road truck flee command sent; driver=\(IsDefined(driver))");
      this.ShowMessage("TRAUMA TEAM: PATIENT EXTRACTED");
    };
    if this.roadDepartTick > 0 && this.ticks >= this.roadDepartTick + 20 {
      if this.roadCleanupTick == 0 {
        this.roadCleanupTick = this.ticks;
        // Unmount before vehicle cleanup; despawning the AV with mounted
        // passengers caused a native crash in an earlier build.
        for npc in this.units {
          if IsDefined(npc) && VehicleComponent.IsMountedToVehicle(npc.GetGame(), npc) {
            GameInstance.GetWorkspotSystem(npc.GetGame()).UnmountFromVehicle(this.truck, npc, true);
          };
        };
      } else if this.ticks == this.roadCleanupTick + 1 {
        this.ClearCrew();
        this.crewClearedTick = this.ticks;
      } else if this.ticks >= this.roadCleanupTick + 2 {
        this.system.RequestDespawn(this.truck.GetEntityID());
        ModLog(n"TraumaTeamSubscriptions", "Road truck despawn requested after crew cleanup");
        this.Finish();
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

  private func PatientStillNearby() -> Bool {
    return IsDefined(this.system) && this.system.TTIsPatientNearby(this.corpse, this.player, this.incidentPosition);
  }

  private func CancelAbandoned() -> Void {
    ModLog(n"TraumaTeamSubscriptions", "Response cancelled silently; patient unloaded or player left scene");
    this.Finish();
  }

  public func Tick() -> Void {
    if this.finished { return; };
    this.ticks += 1;
    if IsDefined(this.system) { this.system.TTPrunePendingResponse(); };
    if !this.recovered && !this.PatientStillNearby() {
      this.CancelAbandoned();
      return;
    };
    // Road arrivals can take a minute to park and dismount before recovery.
    if !IsDefined(this.system) || !IsDefined(this.player) || this.ticks > 180 {
      ModLog(n"TraumaTeamSubscriptions", "Response timed out or lost player/system");
      this.Finish(); return;
    };
    let roadCrewCasualty: Bool = false;
    if this.roadTruckSeen && this.roadDepartTick == 0 {
      for npc in this.units {
        if IsDefined(npc) && !ScriptedPuppet.IsAlive(npc) { roadCrewCasualty = true; };
      };
    };
    if this.roadTruckSeen && this.roadDepartTick == 0 && (!IsDefined(this.truck) || this.truck.IsDestroyed() || roadCrewCasualty) {
      this.HandleRoadLoss();
      if this.finished { return; };
    };
    if IsDefined(this.av) { this.AttachPassengers(this.av); };
    if IsDefined(this.truck) { this.AttachPassengers(this.truck); };
    this.ReleaseRoadCrew();
    if this.roadDepartTick == 0 && IsDefined(this.medic) && !ScriptedPuppet.IsAlive(this.medic) {
      if this.roadTruckSeen && this.roadDepartTick == 0 {
        this.HandleRoadLoss();
        if this.finished { return; };
      } else {
        ModLog(n"TraumaTeamSubscriptions", "Recovery medic killed; AV aborting without crew");
        this.Finish(); return;
      };
    };
    if this.replacementEvac {
      this.TickReplacementEvac();
      if this.roadBoardingTick > 0 { this.TickRoadDeparture(); };
      if !this.finished { this.ScheduleTick(); };
      return;
    };
    if !this.unitsRequested && !IsDefined(this.av) && this.truckRequest == 0u && this.ticks > 14 {
      ModLog(n"TraumaTeamSubscriptions", "AV callback timed out; requesting road recovery");
      if this.avRequest != 0u {
        this.system.CancelSpawnRequest(this.avRequest);
        this.avRequest = 0u;
      };
      this.RequestRoadTruck();
    };
    this.TrackAVLanding();
    if !this.recovered && IsDefined(this.corpse) && IsDefined(this.medic) {
      this.CheckBlockedMedic();
      if !VehicleComponent.IsMountedToVehicle(this.medic.GetGame(), this.medic) {
        let distance: Float = Vector4.Distance2D(this.medic.GetWorldPosition(), this.corpse.GetWorldPosition());
        if distance > 1.25 && AbsF(distance - this.previousRouteDistance) < 0.15 {
          this.medicStallTicks += 1;
        } else {
          this.medicStallTicks = 0;
        };
        this.previousRouteDistance = distance;
        if this.medicStallTicks >= 8 && !IsDefined(this.truck) && distance > 5.0 {
          ArrayRemove(this.patientOrders, this.medic);
          this.medicStallTicks = 0;
          ModLog(n"TraumaTeamSubscriptions", "Medic stalled; refreshing route to patient");
        };
      };
      if this.MedicAtPatient() {
        this.recovered = true;
        this.recoveryTick = this.ticks;
        this.retreatStallTicks = 0;
        this.previousRetreatDistance = 0.0;
        ModLog(n"TraumaTeamSubscriptions", "Medic reached corpse; simulating pickup");
        // Use the game's body-disposal event. Iterating a dead puppet's visual
        // components caused repeatable native access violations.
        let hide: ref<HidePuppetDelayEvent> = new HidePuppetDelayEvent();
        hide.m_target = this.corpse;
        this.corpse.QueueEvent(hide);
        if IsDefined(this.truck) {
          let truckPosition: Vector4 = this.truck.GetWorldPosition();
          let nav: ref<AINavigationSystem> = GameInstance.GetAINavigationSystem(this.corpse.GetGame());
          let walkablePoint: Vector4;
          if nav.TryToFindNavmeshPointAroundPoint(this.corpse, truckPosition, this.corpse.GetWorldOrientation(), Vector4(1.0, 1.0, 2.0, 0.0), 12, 3.0, walkablePoint, true) {
            this.extraction = walkablePoint;
          };
          ArrayClear(this.retreatOrders);
          ModLog(n"TraumaTeamSubscriptions", s"Road extraction beside stopped truck at \(this.extraction)");
        } else if IsDefined(this.av) {
          if !this.entrySet {
            this.extraction = this.medic.GetWorldPosition();
            this.entrySet = true;
          };
          ModLog(n"TraumaTeamSubscriptions", s"AV returning to original dismount at \(this.extraction)");
        };
        for responder in this.units {
          if IsDefined(responder) {
            responder.GetTargetTrackerComponent().ClearThreats();
            GameObject.ChangeAttitudeToNeutral(responder, this.player);
            for enemy in this.patientEnemies { if IsDefined(enemy) { GameObject.ChangeAttitudeToNeutral(responder, enemy); }; };
            this.SendToEntry(responder);
          };
        };
      };
    };
    if !this.recovered && this.extractionArrivalTick == 0 && this.ticks % 4 == 0 {
      this.CapturePatientThreats(this.corpse);
      this.CapturePatientThreats(this.medic);
      this.CaptureNearbyEnemies();
      for responder in this.units {
        this.CapturePatientThreats(responder);
        this.EngagePatientEnemies(responder);
      };
    };
    if this.extractionArrivalTick == 0 {
      for responder in this.units {
        if this.recovered {
          this.SendToEntry(responder);
        }
        else { this.SendToCorpse(responder); };
      };
    };
    if this.recovered && this.extractionArrivalTick == 0 && IsDefined(this.medic) {
      let retreatDistance: Float = Vector4.Distance2D(this.medic.GetWorldPosition(), this.extraction);
      if retreatDistance > 4.0 && AbsF(retreatDistance - this.previousRetreatDistance) < 0.15 {
        this.retreatStallTicks += 1;
      } else { this.retreatStallTicks = 0; };
      this.previousRetreatDistance = retreatDistance;
      if this.retreatStallTicks >= 12 && !IsDefined(this.truck) && !IsDefined(this.av) {
        ArrayRemove(this.retreatOrders, this.medic);
        this.SendToEntry(this.medic);
        this.retreatStallTicks = 0;
        ModLog(n"TraumaTeamSubscriptions", "Medic stalled during ground retreat; refreshing route");
      };
    };
    if this.recovered && this.extractionArrivalTick == 0 && IsDefined(this.av) && this.ticks == this.recoveryTick + 15 {
      for responder in this.units {
        if IsDefined(responder) && ScriptedPuppet.IsAlive(responder) && Vector4.Distance(responder.GetWorldPosition(), this.extraction) > 5.0 && !ArrayContains(this.avRetreatRetried, responder) {
          ArrayRemove(this.retreatOrders, responder);
          this.SendToEntry(responder);
          ArrayPush(this.avRetreatRetried, responder);
          ModLog(n"TraumaTeamSubscriptions", s"Retried AV return; distance=\(Vector4.Distance(responder.GetWorldPosition(), this.extraction))");
        };
      };
    };
    if this.recovered && this.extractionArrivalTick == 0 && IsDefined(this.medic) && this.ticks > this.recoveryTick + 3 {
      let teamAtExtraction: Bool = true;
      for responder in this.units {
        if IsDefined(responder) && ScriptedPuppet.IsAlive(responder) && (IsDefined(this.truck) && Vector4.Distance2D(responder.GetWorldPosition(), this.truck.GetWorldPosition()) > 7.0 || IsDefined(this.av) && Vector4.Distance(responder.GetWorldPosition(), this.extraction) > 5.0 || !IsDefined(this.truck) && !IsDefined(this.av) && Vector4.Distance(responder.GetWorldPosition(), this.extraction) > 6.0) {
          teamAtExtraction = false;
        };
      };
      if teamAtExtraction || IsDefined(this.truck) && this.ticks > this.recoveryTick + 25 {
        this.extractionArrivalTick = this.ticks;
        if IsDefined(this.truck) { this.BeginRoadBoarding(); }
        else { this.HoldAtEntry(); };
        ModLog(n"TraumaTeamSubscriptions", "Recovery squad at extraction");
      };
    };
    if this.recovered && IsDefined(this.av) && this.extractionArrivalTick == 0 && this.crewClearedTick == 0 && this.ticks >= this.recoveryTick + 50 {
      ModLog(n"TraumaTeamSubscriptions", "AV return timed out; releasing landing zone");
      this.ClearCrew();
      this.crewClearedTick = this.ticks;
    };
    if this.extractionArrivalTick > 0 && IsDefined(this.truck) { this.TickRoadDeparture(); };
    if this.extractionArrivalTick > 0 && !IsDefined(this.truck) && this.crewClearedTick == 0 && this.ticks >= this.extractionArrivalTick + 3 {
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
      if this.crewClearedTick == 0 && this.roadDepartTick == 0 {
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

public class WETraumaDespawnCallback extends DelayCallback {
  public let system: wref<PreventionSpawnSystem>;
  public let target: EntityID;
  public func Call() -> Void {
    if IsDefined(this.system) { this.system.RequestDespawn(this.target); };
  }
}

public class WETraumaArrivalTick extends DelayCallback {
  public let response: ref<WETraumaResponse>;
  public func Call() -> Void {
    if IsDefined(this.response) { this.response.CountdownTick(); };
  }
}
