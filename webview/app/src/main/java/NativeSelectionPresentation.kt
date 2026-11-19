package io.github.yawasau.speedbackup.webview

import org.json.JSONObject

/** Presentation only: never replaces catalog keys, labels or selection payloads. */
internal data class NativeSelectionPresentation(val name:String,val detail:String,val icon:String,val friendly:Boolean=false)
private val selectionRowId=Regex("row-[0-9]+")
internal fun nativeSelectionPresentation(row:JSONObject):NativeSelectionPresentation? {
    val id=row.optString("pkg")
    val label=row.optString("label")
    // Selection catalogs use row-N identities; installed/removed apps keep their icons.
    if(!id.matches(selectionRowId)||row.optString("displayPackage").isNotEmpty())return null
    val suffix=listOf(".tar.zst",".tar.gz",".tar.bz2",".tar.xz",".tar.lz4",".tar.lzma",".tar.lzo",".tar").firstOrNull{label.endsWith(it)}
    val token=if(suffix==null)label else label.removeSuffix(suffix)
    return when(token){
        "wifi"->NativeSelectionPresentation("Wi-Fi設定","已儲存的 Wi-Fi 網路與連線設定。","backup_wifi",true)
        "@telephony:messages"->NativeSelectionPresentation("訊息（簡訊／多媒體訊息）","簡訊與多媒體訊息紀錄。","backup_messages",true)
        "@telephony:calls"->NativeSelectionPresentation("通話紀錄","撥出、接聽與未接來電紀錄。","backup_calllogs",true)
        "DCIM"->NativeSelectionPresentation(label,"相機拍攝的相片與影片。","selection-camera")
        "Pictures"->NativeSelectionPresentation(label,"圖片與螢幕截圖。","selection-image")
        "Download"->NativeSelectionPresentation(label,"下載的檔案。","cdn")
        else->NativeSelectionPresentation(label,if(suffix==null)"資料夾內容。" else "備份封存檔。",if(suffix==null)"backup_media" else "Compression_method")
    }
}
