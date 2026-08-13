package io.picklogic.picklogic_android_bridge

import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.Test

internal class PicklogicAndroidBridgePluginTest {
    @Test
    fun requestedAccess_acceptsFullVisualAndAudio() {
        assertTrue(
            hasRequestedMediaAccess(
                35,
                mapOf(
                    "images" to true,
                    "videos" to true,
                    "audio" to true,
                    "partialVisualAccess" to false,
                ),
            ),
        )
    }

    @Test
    fun requestedAccess_acceptsSelectedVisualOnlyWhenAudioIsGranted() {
        val selected = mapOf(
            "images" to false,
            "videos" to false,
            "audio" to true,
            "partialVisualAccess" to true,
        )
        assertTrue(hasRequestedMediaAccess(35, selected))
        assertFalse(hasRequestedMediaAccess(33, selected))
        assertFalse(hasRequestedMediaAccess(35, selected + ("audio" to false)))
    }
}
