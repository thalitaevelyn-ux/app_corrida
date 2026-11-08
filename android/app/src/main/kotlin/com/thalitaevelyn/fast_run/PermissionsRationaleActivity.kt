package com.thalitaevelyn.fast_run

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/**
 * Aberta pelo Health Connect quando o usuário toca em "política de privacidade"
 * / "por que este app pede acesso". O Google exige que ela mostre a política.
 * A URL fica em res/values/strings.xml (privacy_policy_url).
 */
class PermissionsRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url = getString(R.string.privacy_policy_url)
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        finish()
    }
}
