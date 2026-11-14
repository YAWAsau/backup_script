package io.github.yawasau.speedbackup.webview

import androidx.compose.runtime.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import org.json.JSONObject

internal val nativeHomeIconLabels=mapOf(
    "品牌" to "brand",
    "型號" to "model",
    "閃存" to "storage",
    "快閃記憶體" to "storage",
    "闪存" to "storage",
    "硬盘" to "storage",
    "存儲" to "storage",
    "處理器" to "processor",
    "記憶體" to "memory",
    "Android" to "android",
    "核心" to "kernel",
    "SELinux" to "selinux",
    "目前使用者" to "user",
    "執行時間" to "runtime",
    "開機時間" to "uptime",
    "深度睡眠" to "sleep",
    "腳本版本" to "script-version",
    "管理器" to "manager",
    "busybox版本" to "busybox-version",
    "busybox路徑" to "busybox-path",
    "腳本路徑" to "script-path",
    "作者" to "author",
    "支援" to "support")
@Composable internal fun NativeHomeInfoGroup(rows:List<JSONObject>,card:Color,text:Color){
    if(LocalNativeMaterial.current){
        val colors=androidx.compose.material3.MaterialTheme.colorScheme
        Column(verticalArrangement=Arrangement.spacedBy(2.dp)){
            rows.forEachIndexed { index,row -> key(index,row.getString("label")){
                NativeSettingSegment(index,rows.size){
                CompositionLocalProvider(LocalNativeSettingIcon provides row.optString("iconKey","unknown")){
                    androidx.compose.material3.ListItem(
                        content={androidx.compose.material3.Text(row.getString("label"),style=androidx.compose.material3.MaterialTheme.typography.bodyLarge.copy(fontSize=androidx.compose.material3.MaterialTheme.typography.bodyLarge.fontSize*LocalNativeUiScale.current,lineHeight=androidx.compose.material3.MaterialTheme.typography.bodyLarge.lineHeight*LocalNativeUiScale.current))},
                        supportingContent={androidx.compose.material3.Text(row.getString("value"),style=androidx.compose.material3.MaterialTheme.typography.bodyMedium.copy(fontSize=androidx.compose.material3.MaterialTheme.typography.bodyMedium.fontSize*LocalNativeUiScale.current,lineHeight=androidx.compose.material3.MaterialTheme.typography.bodyMedium.lineHeight*LocalNativeUiScale.current))},
                        leadingContent={NativeSettingIcon()},
                        verticalAlignment=androidx.compose.ui.Alignment.CenterVertically,
                        shapes=androidx.compose.material3.ListItemDefaults.segmentedShapes(index,rows.size),
                        colors=androidx.compose.material3.ListItemDefaults.colors(containerColor=if(LocalNativeSurfaceBacked.current)Color.Transparent else colors.surfaceBright,contentColor=colors.onSurface,supportingContentColor=colors.onSurfaceVariant),
                        modifier=Modifier.fillMaxWidth())
                }
                }
            }}
        }
    }else{
        NativeComponentCard("miuix",card,text){
            NativePreferenceScale {
                rows.forEachIndexed { index,row -> key(index,row.getString("label")){
                    CompositionLocalProvider(LocalNativeSettingIcon provides row.optString("iconKey","unknown")){
                        top.yukonga.miuix.kmp.basic.BasicComponent(title=row.getString("label"),summary=row.getString("value"),
                            startAction={NativeSettingIcon()},insideMargin=PaddingValues(horizontal=16.dp,vertical=16.dp))
                    }
                }}
            }
        }
    }
}
