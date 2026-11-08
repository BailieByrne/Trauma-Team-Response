module TraumaTeamSubscriptions

@addField(ScriptedPuppetPS)
public persistent let weTraumaSubscriptionState: Int32;

@addField(ScriptedPuppetPS)
public persistent let weTraumaRollVersion: Int32;

@addMethod(NPCPuppet)
public func WEGuaranteedTraumaTier() -> Int32 {
  let id: TweakDBID = this.GetRecordID();
  // Named gig targets; aliases cover repeat appearances in other content.
  if id == t"Character.sts_dtn_04_target" || id == t"Character.sts_hey_spr_06_rebeca_price" || id == t"Character.kab_06_Blake" || id == t"Character.Grayson" { return 3; };
  if id == t"Character.sts_wat_kab_07_jotaro" || id == t"Character.q303_paradise_jotaro" || id == t"Character.sts_hey_rey_08_karubo" || id == t"Character.sts_std_rcr_01_vic_vega" || id == t"Character.sts_ep1_03_target" || id == t"Character.sts_ep1_12_milko_alexis" || id == t"Character.q103_raffen_nash" { return 2; };
  if id == t"Character.sts_wat_kab_107_taki_kenmochi" || id == t"Character.sts_cct_dtn_02_dozy" || id == t"Character.wst_ep1_ctz_107_mausser" || id == t"Character.wwd_05_target" || id == t"Character.gle_01_tucker" || id == t"Character.sts_hey_spr_01_jose" || id == t"Character.sts_wat_kab_101_enemy_scav_officer_shotgun2" || id == t"Character.sts_wat_lch_03_ricky_wu" || id == t"Character.sts_hey_rey_01_gustavo" || id == t"Character.sq018_rey_01_gustavo" || id == t"Character.ina_02_new_big_pete" { return 1; };
  return 0;
}

@addMethod(NPCPuppet)
public func WETraumaChanceByFaction() -> Int32 {
  let affiliation: TweakDBID = this.GetRecord().Affiliation().GetID();
  if affiliation == t"Factions.TraumaTeam" { return 0; };
  if affiliation == t"Factions.Arasaka" || affiliation == t"Factions.Militech" || affiliation == t"Factions.KangTao" || affiliation == t"Factions.NCPD" || affiliation == t"Factions.Barghest" || affiliation == t"Factions.Biotechnica" || affiliation == t"Factions.NetWatch" || affiliation == t"Factions.Zetatech" || affiliation == t"Factions.CityCouncil" || affiliation == t"Factions.SSI" || affiliation == t"Factions.UnaffiliatedCorpo" { return 30; };
  if affiliation == t"Factions.AfterlifeMercs" || affiliation == t"Factions.Unaffiliated" { return 12; };
  if affiliation == t"Factions.Maelstrom" || affiliation == t"Factions.TygerClaws" || affiliation == t"Factions.Valentinos" || affiliation == t"Factions.SixthStreet" || affiliation == t"Factions.VoodooBoys" || affiliation == t"Factions.TheMox" { return 4; };
  if affiliation == t"Factions.Wraiths" || affiliation == t"Factions.Aldecaldos" { return 1; };
  if affiliation == t"Factions.Scavengers" || affiliation == t"Factions.Animals" { return 0; };
  return 12;
}

// 0 undecided, 1 none, 2 Platinum (including the test hack),
// 3 Silver, 4 Gold. Keep 2 as Platinum for existing saves.
@addMethod(NPCPuppet)
public func WEGetTraumaTier() -> Int32 {
  if !Equals(this.GetNPCType(), gamedataNPCType.Human) || NPCManager.HasVisualTag(this, n"TraumaTeam") { return 0; };
  let state: ref<ScriptedPuppetPS> = this.GetPuppetPS();
  if !IsDefined(state) { return 0; };
  if state.ttForcedPlatinum { return 3; };
  let guaranteed: Int32 = this.WEGuaranteedTraumaTier();
  if guaranteed > 0 {
    state.weTraumaSubscriptionState = guaranteed == 1 ? 3 : guaranteed == 2 ? 4 : 2;
    return guaranteed;
  };
  // Re-evaluate old "no policy" saves once under faction-specific odds.
  if state.weTraumaRollVersion == 0 {
    if state.weTraumaSubscriptionState == 1 { state.weTraumaSubscriptionState = 0; };
    state.weTraumaRollVersion = 1;
  };
  if state.weTraumaSubscriptionState == 2 { return 3; };
  if state.weTraumaSubscriptionState == 3 { return 1; };
  if state.weTraumaSubscriptionState == 4 { return 2; };
  if state.weTraumaSubscriptionState == 1 { return 0; };
  let skull: Bool = Equals(RPGManager.CalculatePowerDifferential(this), gameEPowerDifferential.IMPOSSIBLE)
    || NPCManager.HasVisualTag(this, n"Sumo");
  if !this.IsBoss() && !(this.IsElite() && skull) {
    state.weTraumaSubscriptionState = 1; return 0;
  };
  let chance: Int32 = this.WETraumaChanceByFaction();
  if RandRange(0, 100) >= chance { state.weTraumaSubscriptionState = 1; return 0; };
  let roll: Int32 = RandRange(0, 100);
  state.weTraumaSubscriptionState = roll < 60 ? 3 : roll < 90 ? 4 : 2;
  return this.WEGetTraumaTier();
}

@addMethod(NPCPuppet)
public func WEHasTraumaSubscription() -> Bool {
  return this.WEGetTraumaTier() > 0;
}

// Add the policy to the scanner's abilities panel. Never modify the NPC name.
@wrapMethod(NPCPuppet)
public const func CompileScannerChunks() -> Bool {
  let result: Bool = wrappedMethod();
  let target: wref<NPCPuppet> = this as NPCPuppet;
  if !result || !IsDefined(target) { return result; };
  let tier: Int32 = target.WEGetTraumaTier();
  if tier == 0 { return result; };
  let scanner = GameInstance.GetBlackboardSystem(this.GetGame()).Get(GetAllBlackboardDefs().UI_ScannerModules);
  if !IsDefined(scanner) { return result; };
  let chunk: ref<ScannerAbilities> = FromVariant<ref<ScannerAbilities>>(scanner.GetVariant(GetAllBlackboardDefs().UI_ScannerModules.ScannerAbilities));
  let abilities: array<wref<GameplayAbility_Record>>;
  if IsDefined(chunk) { abilities = chunk.GetAbilities(); }
  else { chunk = new ScannerAbilities(); };
  let id: TweakDBID = tier == 1 ? t"Ability.TTTraumaSilver" : tier == 2 ? t"Ability.TTTraumaGold" : t"Ability.TTTraumaPlatinum";
  let ability: wref<GameplayAbility_Record> = TweakDBInterface.GetGameplayAbilityRecord(id);
  if IsDefined(ability) && !ArrayContains(abilities, ability) {
    ArrayPush(abilities, ability);
    chunk.Set(abilities);
    scanner.SetVariant(GetAllBlackboardDefs().UI_ScannerModules.ScannerAbilities, ToVariant(chunk), true);
  };
  return result;
}
