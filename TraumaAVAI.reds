// The stock MaxTac AV tells every passenger to attack the player on exit.
@addMethod(VehicleObject)
public final func TTIsTraumaAV() -> Bool {
  let record: TweakDBID = this.GetRecordID();
  return record == t"Vehicle.TTTraumaResponseAV" || record == t"Vehicle.TTTraumaGoldAV" || record == t"Vehicle.TTTraumaSilverAV";
}

// The stock MaxTac AV tells every passenger to attack the player on exit.
// Trauma Team protects its patient instead; ordinary hit reactions still
// allow responders to retaliate if the player shoots them.
@wrapMethod(DetectPlayerFromAV)
protected func Activate(context: ScriptExecutionContext) -> Void {
  let owner: wref<GameObject> = ScriptExecutionContext.GetOwner(context);
  let vehicle: wref<VehicleObject>;
  VehicleComponent.GetVehicleFromID(owner.GetGame(), owner.GetEntityID(), vehicle);
  if IsDefined(vehicle) && vehicle.TTIsTraumaAV() { return; };
  wrappedMethod(context);
}

// Do not enlist this private ambulance in the police prevention system.
@wrapMethod(RegisterPsychoSquadPassengers)
protected func Activate(context: ScriptExecutionContext) -> Void {
  let owner: wref<GameObject> = ScriptExecutionContext.GetOwner(context);
  let vehicle: wref<VehicleObject>;
  VehicleComponent.GetVehicleFromID(owner.GetGame(), owner.GetEntityID(), vehicle);
  if IsDefined(vehicle) && vehicle.TTIsTraumaAV() { return; };
  wrappedMethod(context);
}

// Capture the real AV occupants before the stock task schedules their jump.
@wrapMethod(GetOffThePsychoSquadAV)
protected func Activate(context: ScriptExecutionContext) -> Void {
  let owner: wref<GameObject> = ScriptExecutionContext.GetOwner(context);
  let vehicle: wref<VehicleObject>;
  VehicleComponent.GetVehicleFromID(owner.GetGame(), owner.GetEntityID(), vehicle);
  if IsDefined(vehicle) && vehicle.TTIsTraumaAV() {
    GameInstance.GetPreventionSpawnSystem(owner.GetGame()).TTRecordPassengers(vehicle);
  };
  wrappedMethod(context);
}

// The native AV ascends as soon as it has no mounted passengers. Hold the
// Trauma AV in place until the recovery squad reaches its extraction point.
@wrapMethod(IsPsychoSquadAvWithoutPassangers)
protected func Check(context: ScriptExecutionContext) -> AIbehaviorConditionOutcomes {
  let owner: wref<GameObject> = ScriptExecutionContext.GetOwner(context);
  let vehicle: wref<VehicleObject>;
  VehicleComponent.GetVehicleFromID(owner.GetGame(), owner.GetEntityID(), vehicle);
  if IsDefined(vehicle) && vehicle.TTIsTraumaAV() {
    if GameInstance.GetPreventionSpawnSystem(owner.GetGame()).TTShouldHoldAV(vehicle) { return AIbehaviorConditionOutcomes.False; };
  };
  return wrappedMethod(context);
}

// The MaxTac tree can cloak the AV while its team is still on foot, leaving
// only landing lights and sound. Keep the Trauma AV visible during recovery.
@wrapMethod(TurnOnPsychoSquadAvCammo)
protected func Activate(context: ScriptExecutionContext) -> Void {
  let owner: wref<GameObject> = ScriptExecutionContext.GetOwner(context);
  let vehicle: wref<VehicleObject>;
  VehicleComponent.GetVehicleFromID(owner.GetGame(), owner.GetEntityID(), vehicle);
  if IsDefined(vehicle) && vehicle.TTIsTraumaAV() {
    if GameInstance.GetPreventionSpawnSystem(owner.GetGame()).TTShouldHoldAV(vehicle) { return; };
  };
  wrappedMethod(context);
}

@wrapMethod(TurnOnPsychoSquadAvCammoImmediatly)
protected func Activate(context: ScriptExecutionContext) -> Void {
  let owner: wref<GameObject> = ScriptExecutionContext.GetOwner(context);
  let vehicle: wref<VehicleObject>;
  VehicleComponent.GetVehicleFromID(owner.GetGame(), owner.GetEntityID(), vehicle);
  if IsDefined(vehicle) && vehicle.TTIsTraumaAV() {
    if GameInstance.GetPreventionSpawnSystem(owner.GetGame()).TTShouldHoldAV(vehicle) { return; };
  };
  wrappedMethod(context);
}

// A cloak task may already have queued its delayed effect before the AV was
// attached to the response, so guard the delayed callback as well.
@wrapMethod(PsychoSquadAvHelperClass)
private func OnTurnOnPsychoSquadAvCammoEventDelayed(evt: ref<TurnOnPsychoSquadAvCammoEvent>) -> Void {
  let vehicle: wref<VehicleObject> = evt.go as VehicleObject;
  if IsDefined(vehicle) && vehicle.TTIsTraumaAV() {
    if GameInstance.GetPreventionSpawnSystem(vehicle.GetGame()).TTShouldHoldAV(vehicle) { return; };
  };
  wrappedMethod(evt);
}
