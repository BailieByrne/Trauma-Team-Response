// A distinct quickhack status effect is the diagnostic trigger. It persists
// the policy flag even after the quickhack effect expires.
@addField(ScriptedPuppetPS)
public let ttResponseRequested: Bool;

@addField(ScriptedPuppetPS)
public persistent let ttForcedPlatinum: Bool;

@addMethod(NPCPuppet)
public func TTRequestRecovery(player: ref<PlayerPuppet>) -> Void {
  if !IsDefined(player) || !this.WEHasTraumaSubscription() { return; };
  let state: ref<ScriptedPuppetPS> = this.GetPuppetPS();
  if !IsDefined(state) || state.ttResponseRequested { return; };
  if GameInstance.GetPreventionSpawnSystem(this.GetGame()).TTStartResponse(this, player, this.WEGetTraumaTier()) {
    state.ttResponseRequested = true;
  };
}

@wrapMethod(NPCPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
  wrappedMethod(evt);
  if IsDefined(evt.staticData) && Equals(evt.staticData.GetID(), t"BaseStatusEffect.TraumaTeamTest") {
    let state: ref<ScriptedPuppetPS> = this.GetPuppetPS();
    if IsDefined(state) {
      state.ttForcedPlatinum = true;
      state.weTraumaSubscriptionState = 2;
      ModLog(n"TraumaTeamSubscriptions", "Test quickhack forced Platinum policy");
    };
  };
}

// Some NPC deaths, including police, do not enter the normal kill-reward path.
@wrapMethod(NPCPuppet)
protected cb func OnDeath(evt: ref<gameDeathEvent>) -> Bool {
  wrappedMethod(evt);
  if this.IsDead() { this.TTRequestRecovery(evt.instigator as PlayerPuppet); };
}

// A save load can discard delayed callbacks while the prevention system stays
// alive. Reset the old dispatch before the new player session begins.
@wrapMethod(PlayerPuppet)
protected cb func OnGameAttached() -> Bool {
  wrappedMethod();
  GameInstance.GetPreventionSpawnSystem(this.GetGame()).TTResetForSaveLoad();
}

@wrapMethod(ScriptedPuppet)
protected func RewardKiller(killer: wref<GameObject>, killType: gameKillType, isAnyDamageNonlethal: Bool) -> Void {
  let player: ref<PlayerPuppet> = killer as PlayerPuppet;
  let victim: ref<NPCPuppet> = this as NPCPuppet;
  let covered: Bool = IsDefined(player) && IsDefined(victim)
    && NotEquals(killType, gameKillType.Defeat) && victim.WEHasTraumaSubscription();
  wrappedMethod(killer, killType, isAnyDamageNonlethal);
  if covered {
    victim.TTRequestRecovery(player);
  };
}
