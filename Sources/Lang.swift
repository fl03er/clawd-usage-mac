// UI language: Korean or English. "auto" follows the system's preferred language.

import Foundation

var uiLang = "auto"   // "auto", "ko" or "en"; set from the settings

var isKo: Bool { uiLang == "ko" || (uiLang == "auto" && (Locale.preferredLanguages.first ?? "").hasPrefix("ko")) }

func L(_ ko: String, _ en: String) -> String { isKo ? ko : en }
