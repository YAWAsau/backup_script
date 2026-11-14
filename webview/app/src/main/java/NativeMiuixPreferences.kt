package io.github.yawasau.speedbackup.webview

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import top.yukonga.miuix.kmp.basic.DropdownEntry
import top.yukonga.miuix.kmp.basic.DropdownItem
import top.yukonga.miuix.kmp.preference.WindowDropdownPreference
import org.json.JSONObject

@Composable internal fun NativePreferenceScale(content:@Composable ()->Unit){
    val density=LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(density.density,density.fontScale*LocalNativeUiScale.current),
        LocalNativeUiScale provides 1f,content=content)
}

@Composable internal fun NativeMiuixDropdownPreference(title:String,summary:String,options:List<JSONObject>,value:String,
    enabled:Boolean=true,onExpandedChange:(Boolean)->Unit={},onSelect:(String)->Unit){
    val select by rememberUpdatedState(onSelect)
    val entries=remember(options,value){options.map { option -> DropdownItem(text=option.getString("label"),enabled=!option.optBoolean("disabled"),
        selected=option.getString("value")==value,onClick={select(option.getString("value"))}) }}
    NativePreferenceScale {
        WindowDropdownPreference(entry=DropdownEntry(entries),title=title,summary=summary.ifBlank{null},enabled=enabled,
            insideMargin=PaddingValues(vertical=12.dp),startAction=nativeSettingIconSlot(enabled),onExpandedChange=onExpandedChange)
    }
}
