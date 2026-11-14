package io.github.yawasau.speedbackup.webview

import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.CodingErrorAction

/** Incremental UTF-8 and terminal escape parser; no HTML interpretation. */
internal class NativeLogDecoder(private val log:(String,List<Run>)->Unit,private val progress:(String)->Unit,startOffset:Long=0){
    var position:Long=startOffset;private set
    data class Run(var text:String,val color:Long,val weight:Int)
    private val decoder=Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPLACE).onUnmappableCharacter(CodingErrorAction.REPLACE)
    private var carry=ByteArray(0)
    private var line=StringBuilder()
    private data class WorkingRun(val text:StringBuilder,val color:Long,val weight:Int)
    private var runs=mutableListOf<WorkingRun>()
    private var escape=""
    private var osc=false
    private var cr=false
    private var color=0L
    private var bold=false
    fun reset(startOffset:Long=0){position=startOffset;decoder.reset();carry=ByteArray(0);line=StringBuilder();runs.clear();escape="";osc=false;cr=false;color=0;bold=false}
    fun bytes(bytes:ByteArray,end:Boolean=false){
        val input=ByteBuffer.wrap(carry+bytes);val out=CharBuffer.allocate(input.remaining()+2)
        decoder.decode(input,out,end);carry=ByteArray(input.remaining()).also{input.get(it)}
        if(end)decoder.flush(out)
        out.flip();consume(out.toString())
        if(end){flush();decoder.reset();carry=ByteArray(0)}
    }
    private fun flush(){if(line.isNotBlank())log(line.toString(),runs.map{Run(it.text.toString(),it.color,it.weight)});line=StringBuilder();runs=mutableListOf()}
    private fun rgb(r:Int,g:Int,b:Int)=0xff000000L or (r.toLong() shl 16) or (g.toLong() shl 8) or b.toLong()
    private fun sgr(value:String){
        val args=value.split(';').map{it.toIntOrNull()?:0};var i=0
        while(i<args.size){when(val n=args[i]){
            0->{color=0;bold=false};1->bold=true;22->bold=false;39->color=0
            in 30..37->color=terminalAnsiColor(n-30);in 90..97->color=terminalAnsiColor(n-90+8)
            38->if(args.getOrNull(i+1)==5&&args.getOrNull(i+2) in 0..255){color=terminalAnsiColor(args[i+2]);i+=2}else if(args.getOrNull(i+1)==2&&i+4<args.size&&args.subList(i+2,i+5).all{it in 0..255}){color=rgb(args[i+2],args[i+3],args[i+4]);i+=4}
            48->if(args.getOrNull(i+1)==5&&i+2<args.size)i+=2 else if(args.getOrNull(i+1)==2&&i+4<args.size)i+=4
        };i++}
    }
    private fun consume(text:String){for(ch in text){
        position+=when{ch.isHighSurrogate()->4L;ch.isLowSurrogate()->0L;ch.code<128->1L;ch.code<2048->2L;else->3L}
        if(osc){if(ch=='\u0007'||(escape=="\u001b"&&ch=='\\')){osc=false;escape=""}else escape=if(ch=='\u001b')ch.toString() else "";continue}
        if(escape.isNotEmpty()){
            escape+=ch
            if(escape=="\u001b]"){osc=true;escape=""}else if(escape.length==2&&ch!='[')escape="" else if(escape.startsWith("\u001b[")&&escape.length>2&&ch in '@'..'~'){if(ch=='m')sgr(escape.substring(2,escape.length-1));escape=""}else if(escape.length>128)escape=""
            continue
        }
        if(ch=='\u001b'){escape=ch.toString();continue}
        if(ch=='\r'){progress(line.toString());cr=true;continue}
        if(ch=='\n'){flush();cr=false;continue}
        if(cr){line=StringBuilder();runs=mutableListOf();cr=false}
        if(ch=='\b'){if(line.isNotEmpty())line.deleteCharAt(line.length-1);runs.lastOrNull()?.let{if(it.text.isNotEmpty())it.text.deleteCharAt(it.text.length-1);if(it.text.isEmpty())runs.removeAt(runs.lastIndex)};continue}
        if(ch=='\t'||ch>=' '){line.append(ch);val last=runs.lastOrNull();val weight=if(bold)700 else 400;if(last!=null&&last.color==color&&last.weight==weight)last.text.append(ch) else runs.add(WorkingRun(StringBuilder().append(ch),color,weight));if(line.length>8192||runs.size>24)flush()}
    }}
}

private fun terminalRgb(r:Int,g:Int,b:Int)=0xff000000L or (r.toLong() shl 16) or (g.toLong() shl 8) or b.toLong()
internal fun terminalAnsiColor(n:Int):Long{
        require(n in 0..255)
        if(n<16)return longArrayOf(0xff000000,0xffcd3131,0xff0dbc79,0xffe5a000,0xff2472c8,0xffbc3fbc,0xff11a8cd,0xffe5e5e5,0xff666666,0xfff14c4c,0xff23d18b,0xfff5c542,0xff3b8eea,0xffd670d6,0xff29b8db,0xffffffff)[n]
        if(n<232){val x=n-16;val levels=intArrayOf(0,95,135,175,215,255);return terminalRgb(levels[x/36],levels[x/6%6],levels[x%6])}
        val v=8+(n-232)*10;return terminalRgb(v,v,v)
    }
