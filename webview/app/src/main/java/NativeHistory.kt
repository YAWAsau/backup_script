package io.github.yawasau.speedbackup.webview
import org.json.JSONObject

/** Preserve every decoded record while bounding each render transaction. */
internal fun partitionHistoryRows(rows:Iterable<JSONObject>):List<List<JSONObject>> {
    val chunks=mutableListOf<List<JSONObject>>();var chunk=mutableListOf<JSONObject>();var characters=0
    for(row in rows){
        val size=row.getString("label").length
        require(size<=8193)
        if(chunk.size>=280||characters+size>60000){chunks+=chunk;chunk=mutableListOf();characters=0}
        chunk+=row;characters+=size
    }
    if(chunk.isNotEmpty()||chunks.isEmpty())chunks+=chunk
    return chunks
}
