package io.picklogic.picklogic_android_bridge

import kotlin.test.assertFalse
import kotlin.test.assertEquals
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

    @Test
    fun imageSortUsesDisplayedCaptureFallbackAndStableId() {
        assertEquals(
            "CASE WHEN datetaken > 0 THEN datetaken / 1000 ELSE date_modified END DESC, _id DESC",
            mediaSortOrder(hasImageColumns = true),
        )
        assertEquals(
            "date_modified DESC, _id DESC",
            mediaSortOrder(hasImageColumns = false),
        )
    }

    @Test
    fun sourceHintIgnoresSystemImportOwners() {
        assertEquals(
            "Screenshots",
            mediaSourceHint("com.android.shell", "Screenshots", "Screenshots"),
        )
        assertEquals(
            "com.example.camera",
            mediaSourceHint("com.example.camera", "Camera", "Camera"),
        )
    }
}
