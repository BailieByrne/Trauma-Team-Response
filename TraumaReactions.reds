// A recovery crew has already been dispatched to a casualty. Do not let the
// ordinary body-discovery reaction interrupt its movement or startle animation.
@wrapMethod(ReactionManagerComponent)
protected func HandleStimEvent(stimData: ref<StimEventTaskData>) -> Void {
  if IsDefined(stimData) && IsDefined(stimData.cachedEvt) && Equals(stimData.cachedEvt.GetStimType(), gamedataStimType.DeadBody) {
    let owner: wref<NPCPuppet> = this.GetOwnerPuppet() as NPCPuppet;
    if IsDefined(owner) && GameInstance.GetPreventionSpawnSystem(owner.GetGame()).TTIsResponder(owner) { return; };
  };
  wrappedMethod(stimData);
}
