package com.kyant.backdrop.catalog.utils
import kotlinx.coroutines.android.awaitFrame as androidAwaitFrame
suspend fun awaitFrame() { androidAwaitFrame() }
