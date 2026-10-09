package com.xayah.dex;

import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteStatement;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.math.BigInteger;
import java.nio.ByteBuffer;
import java.util.*;

/** Re-namespace colliding imported identities in private copies, without changing history content. */
final class TimelineIdentity {
    private static final String[] TABLES={"semantic_segment_table","edited_segment_table","aux_semantic_segment_table"};
    private static void need(boolean ok,String reason)throws IOException { TimelineDatabase.require(ok,reason); }
    private static String mapped(String id,String gaia,boolean semantic)throws Exception {
        byte[] name=("SpeedBackupTimeline\u0000"+gaia+"\u0000"+id).getBytes(StandardCharsets.UTF_8);
        return semantic?UUID.nameUUIDFromBytes(name).toString():new BigInteger(1,MessageDigest.getInstance("SHA-1").digest(name)).toString(16);
    }
    private static long varint(byte[] data,int[] at)throws IOException {
        long value=0;
        for(int shift=0;shift<64;shift+=7){need(at[0]<data.length,"timeline_proto_truncated");int b=data[at[0]++]&255;if(shift==63)need((b&254)==0,"timeline_proto_varint_invalid");value|=(long)(b&127)<<shift;if((b&128)==0)return value;}
        throw new IOException("timeline_proto_varint_invalid");
    }
    private static void writeVarint(ByteArrayOutputStream out,long value){while((value&~127L)!=0){out.write((int)value&127|128);value>>>=7;}out.write((int)value);}
    private static String ascii(byte[] data,int start,int end){
        if(end-start<1||end-start>256)return null;
        for(int i=start;i<end;i++)if(data[i]<32||data[i]>126)return null;
        return new String(data,start,end-start,StandardCharsets.US_ASCII);
    }
    // Nested messages are inspected for references. Unknown identity references fail closed;
    // only the verified top-level semantic ID field (6, length-delimited) is rewritten.
    private static void references(byte[] data,Map<String,String> map,int depth)throws IOException {
        if(depth>16)return;
        int[] at={0};List<byte[]> nested=new ArrayList<>();List<String> values=new ArrayList<>();
        try {
            while(at[0]<data.length){long tag=varint(data,at);need(tag>>>3>0,"timeline_proto_tag_invalid");int wire=(int)tag&7;
                if(wire==0)varint(data,at);
                else if(wire==1||wire==5)at[0]+=wire==1?8:4;
                else if(wire==2){long size=varint(data,at);need(size>=0&&size<=data.length-at[0],"timeline_proto_truncated");int end=at[0]+(int)size;String value=ascii(data,at[0],end);if(value!=null)values.add(value);nested.add(Arrays.copyOfRange(data,at[0],end));at[0]=end;}
                else throw new IOException("timeline_proto_wire_invalid");
                need(at[0]<=data.length,"timeline_proto_truncated");
            }
        }catch(IOException notMessage){return;}
        for(String value:values)need(!map.containsKey(value),"timeline_identity_reference_unsupported");
        for(byte[] child:nested)references(child,map,depth+1);
    }
    static byte[] rewrite(byte[] data,String id,Map<String,String> map,boolean semantic)throws Exception {
        String replacement=map.get(id);int own=0;int[] at={0};ByteArrayOutputStream out=new ByteArrayOutputStream(data.length+40);
        while(at[0]<data.length){int start=at[0];long tag=varint(data,at);need(tag>>>3>0,"timeline_proto_tag_invalid");int wire=(int)tag&7;
            if(wire==0)varint(data,at);
            else if(wire==1||wire==5)at[0]+=wire==1?8:4;
            else if(wire==2){long size=varint(data,at);need(size>=0&&size<=data.length-at[0],"timeline_proto_truncated");int end=at[0]+(int)size;String value=ascii(data,at[0],end);
                if((tag>>>3)==6&&semantic){need(id.equals(value),"timeline_identity_field_mismatch");own++;
                    if(replacement!=null){writeVarint(out,tag);byte[] bytes=replacement.getBytes(StandardCharsets.UTF_8);writeVarint(out,bytes.length);out.write(bytes);at[0]=end;continue;}
                } else {need(value==null||!map.containsKey(value),"timeline_identity_reference_unsupported");references(Arrays.copyOfRange(data,at[0],end),map,0);}
                at[0]=end;
            }else throw new IOException("timeline_proto_wire_invalid");
            need(at[0]<=data.length,"timeline_proto_truncated");out.write(data,start,at[0]-start);
        }
        if(semantic)need(own==1,"timeline_identity_field_missing");return out.toByteArray();
    }
    static boolean rekeyConflicts(File input,File liveOd,File liveAux,String gaia)throws Exception {
        Set<String> reserved=new HashSet<>(),semantic=new HashSet<>();Map<String,String> map=new LinkedHashMap<>();
        Set<Long> databases=new HashSet<>();Set<String> origins=new HashSet<>();Map<Long,Long> databaseMap=new LinkedHashMap<>();
        try(SQLiteDatabase db=TimelineDatabase.open(liveOd,TimelineDatabase.RO);Cursor c=db.rawQuery("SELECT database_id,origin_id FROM semantic_segment_table WHERE obfuscated_gaia_id IS NOT ?",new String[]{gaia})) {
            while(c.moveToNext()){databases.add(c.getLong(0));if(!c.isNull(1))origins.add(c.getLong(0)+":"+c.getLong(1));}
        }finally{TimelineDatabase.fixSidecars(liveOd);}
        try(SQLiteDatabase db=TimelineDatabase.open(new File(input,"odlh.db"),TimelineDatabase.RO);Cursor c=db.rawQuery("SELECT database_id,origin_id FROM semantic_segment_table",null)) {
            while(c.moveToNext()){long id=c.getLong(0);databases.add(id);if(!c.isNull(1)&&origins.contains(id+":"+c.getLong(1)))databaseMap.put(id,null);}
        }
        for(Long id:new ArrayList<>(databaseMap.keySet())) {
            long next=ByteBuffer.wrap(MessageDigest.getInstance("SHA-256").digest(("SpeedBackupTimelineOrigin\u0000"+gaia+"\u0000"+id).getBytes(StandardCharsets.UTF_8))).getLong()&Long.MAX_VALUE;
            need(next!=0&&databases.add(next),"timeline_origin_namespace_collision");databaseMap.put(id,next);
        }
        for(int i=0;i<TABLES.length;i++){
            Set<String> ids=new HashSet<>();File live=i==2?liveAux:liveOd;
            try(SQLiteDatabase db=TimelineDatabase.open(live,TimelineDatabase.RO);Cursor c=db.rawQuery("SELECT segment_id FROM "+TABLES[i]+" WHERE obfuscated_gaia_id IS NOT ?",new String[]{gaia})){while(c.moveToNext())ids.add(c.getString(0));}
            finally{TimelineDatabase.fixSidecars(live);}reserved.addAll(ids);
            try(SQLiteDatabase db=TimelineDatabase.open(new File(input,i==2?"aux.db":"odlh.db"),TimelineDatabase.RO);Cursor c=db.rawQuery("SELECT segment_id FROM "+TABLES[i],null)){
                while(c.moveToNext()){String id=c.getString(0);reserved.add(id);if(i!=1)semantic.add(id);if(ids.contains(id))map.put(id,null);}
            }
        }
        if(map.isEmpty()&&databaseMap.isEmpty())return false;
        for(String id:new ArrayList<>(map.keySet())){String next=mapped(id,gaia,semantic.contains(id));need(reserved.add(next),"timeline_identity_namespace_collision");map.put(id,next);}
        for(String name:new String[]{"odlh.db","aux.db"})try(SQLiteDatabase db=TimelineDatabase.open(new File(input,name),SQLiteDatabase.OPEN_READWRITE|SQLiteDatabase.NO_LOCALIZED_COLLATORS)){
            db.beginTransaction();try {
                String trigger=null;
                if(name.equals("odlh.db")){trigger=TimelineDatabase.scalar(db,"SELECT sql FROM sqlite_master WHERE type='trigger' AND name='semantic_segment_table_update_timestamp_millis_trigger'");need(trigger!=null&&trigger.startsWith("CREATE TRIGGER"),"timeline_update_trigger_unsupported");db.execSQL("DROP TRIGGER semantic_segment_table_update_timestamp_millis_trigger");}
                if(name.equals("odlh.db"))for(Map.Entry<Long,Long> entry:databaseMap.entrySet()) {
                    ByteArrayOutputStream encoded=new ByteArrayOutputStream();writeVarint(encoded,entry.getKey());
                    try(SQLiteStatement check=db.compileStatement("SELECT count(*) FROM semantic_segment_table WHERE instr(semantic_segment,?)>0")) {
                        check.bindBlob(1,encoded.toByteArray());need(check.simpleQueryForLong()==0,"timeline_origin_reference_unsupported");
                    }
                    db.execSQL("UPDATE semantic_segment_table SET database_id=? WHERE database_id=?",new Object[]{entry.getValue(),entry.getKey()});
                }
                for(int i=0;i<TABLES.length;i++){
                    if((i==2)!=name.equals("aux.db"))continue;
                    try(Cursor c=db.rawQuery("SELECT _id,segment_id,semantic_segment FROM "+TABLES[i]+" ORDER BY _id",null);SQLiteStatement update=db.compileStatement("UPDATE "+TABLES[i]+" SET segment_id=?,semantic_segment=? WHERE _id=?")){
                        while(c.moveToNext()){String id=c.getString(1);byte[] before=c.getBlob(2),after=rewrite(before,id,map,i!=1);String next=map.get(id);
                            if(next!=null){update.bindString(1,next);update.bindBlob(2,after);update.bindLong(3,c.getLong(0));need(update.executeUpdateDelete()==1,"timeline_identity_row_missing");}
                            else need(Arrays.equals(before,after),"timeline_unrelated_identity_changed");
                        }
                    }
                }
                if(trigger!=null)db.execSQL(trigger);db.setTransactionSuccessful();
            }finally{db.endTransaction();}
        }
        return true;
    }
}
