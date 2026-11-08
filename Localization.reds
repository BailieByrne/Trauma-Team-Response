module TraumaTeamSubscriptions.Localization

import Codeware.Localization.*

public class TTLocalization extends ModLocalizationProvider {
  public func GetFallback() -> CName { return n"en-us"; }
  public func GetPackage(language: CName) -> ref<ModLocalizationPackage> {
    return Equals(language, n"en-us") ? new TTEnglish() : null;
  }
}

public class TTEnglish extends ModLocalizationPackage {
  protected func DefineTexts() -> Void {
    this.Text("TT-Test-Name", "Trauma Team Test");
    this.Text("TT-Test-Description", "Marks a human target as a Trauma Team Platinum subscriber. Kill the target to test the response.");
    this.Text("TT-Response-Name", "Trauma Team Response");
    this.Text("TT-Silver-Name", "Trauma Team Silver Subscription");
    this.Text("TT-Silver-Description", "One responder arrives 60 seconds after a lethal death.");
    this.Text("TT-Gold-Name", "Trauma Team Gold Subscription");
    this.Text("TT-Gold-Description", "Two responders arrive 45 seconds after a lethal death.");
    this.Text("TT-Platinum-Name", "Trauma Team Platinum Subscription");
    this.Text("TT-Platinum-Description", "Three responders arrive 30 seconds after a lethal death.");
  }
}
