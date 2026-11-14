package io.github.yawasau.speedbackup.webview

import androidx.compose.runtime.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import org.json.JSONObject

internal fun nativeHomeIconKey(label:String)=when(label){
    "品牌"->"brand";"型號"->"model";"閃存"->"storage";"處理器"->"processor";"記憶體"->"memory"
    "Android"->"android";"核心"->"kernel";"SELinux"->"selinux";"目前使用者"->"user"
    "執行時間"->"runtime";"開機時間"->"uptime";"深度睡眠"->"sleep";"腳本版本"->"script-version"
    "管理器"->"manager";"busybox版本"->"busybox-version";"busybox路徑"->"busybox-path"
    "腳本路徑"->"script-path";"作者"->"author";"支援"->"support";else->"unknown"
}
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
