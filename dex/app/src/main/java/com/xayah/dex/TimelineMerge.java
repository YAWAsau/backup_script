package com.xayah.dex;

import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteStatement;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Combines owned private snapshots only. The caller commits once after validating the union. */
final class TimelineMerge {
    private static final String[] TABLES={"semantic_segment_table","edited_segment_table","aux_semantic_segment_table"};
    private static String fingerprint(Cursor row,boolean semantic,boolean semanticIdentity,String namespace,String databaseNamespace)throws Exception {
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(bytes);
        String id=row.getString(row.getColumnIndexOrThrow("segment_id"));
        for(int i=0;i<row.getColumnCount();i++) {
            String name=row.getColumnName(i);
            if(Arrays.asList("_id","obfuscated_gaia_id").contains(name))continue;
            out.writeUTF(name);int type=row.getType(i);out.writeInt(type);
            if(type==Cursor.FIELD_TYPE_NULL)continue;
            if(type==Cursor.FIELD_TYPE_INTEGER)out.writeLong(name.equals("database_id")&&databaseNamespace!=null?TimelineIdentity.mappedDatabase(row.getLong(i),databaseNamespace):row.getLong(i));
            else if(type==Cursor.FIELD_TYPE_FLOAT)out.writeLong(Double.doubleToLongBits(row.getDouble(i)));
            else {
                byte[] value=type==Cursor.FIELD_TYPE_BLOB?row.getBlob(i):row.getString(i).getBytes(StandardCharsets.UTF_8);
                if(name.equals("segment_id")&&namespace!=null)value=TimelineIdentity.mapped(id,namespace,semanticIdentity).getBytes(StandardCharsets.UTF_8);
                if(name.equals("semantic_segment")&&semantic&&namespace!=null) {
                    Map<String,String> own=new HashMap<>();own.put(id,TimelineIdentity.mapped(id,namespace,true));
                    value=TimelineIdentity.rewrite(value,id,own,true);
                }
                out.writeInt(value.length);out.write(value);
            }
        }
        out.flush();return TimelineDatabase.digest(bytes.toByteArray());
    }
    static long append(File aggregate,File incoming,String namespace)throws Exception {
        long skipped=0;
        // Keep identity columns in equality: equal content under distinct IDs may be referenced.
        Set<String> semanticIds=new HashSet<>();
        for(String table:new String[]{"semantic_segment_table","aux_semantic_segment_table"})try(SQLiteDatabase db=TimelineDatabase.open(new File(incoming,table.startsWith("aux")?"aux.db":"odlh.db"),TimelineDatabase.RO);Cursor c=db.rawQuery("SELECT segment_id FROM "+table,null)){while(c.moveToNext())semanticIds.add(c.getString(0));}
        Map<String,Set<Long>> duplicates=new LinkedHashMap<>();
        Map<String,String> mappedDuplicates=new HashMap<>();Set<Long> mappedOrigins=new HashSet<>();
        for(String table:TABLES) {
            String name=table.startsWith("aux")?"aux.db":"odlh.db";Set<String> existing=new HashSet<>();
            boolean semantic=!table.equals("edited_segment_table");
            try(SQLiteDatabase db=TimelineDatabase.open(new File(aggregate,name),TimelineDatabase.RO);Cursor c=db.rawQuery("SELECT * FROM "+table,null)){while(c.moveToNext())existing.add(fingerprint(c,semantic,semanticIds.contains(c.getString(c.getColumnIndexOrThrow("segment_id"))),null,null));}
            Set<Long> ids=new HashSet<>();duplicates.put(table,ids);
            try(SQLiteDatabase db=TimelineDatabase.open(new File(incoming,name),TimelineDatabase.RO);Cursor c=db.rawQuery("SELECT * FROM "+table,null)) {
                while(c.moveToNext()) {
                    boolean exact=existing.contains(fingerprint(c,semantic,semanticIds.contains(c.getString(c.getColumnIndexOrThrow("segment_id"))),null,null));
                    boolean mapped=!exact&&existing.contains(fingerprint(c,semantic,semanticIds.contains(c.getString(c.getColumnIndexOrThrow("segment_id"))),"merge:"+namespace,null));
                    boolean mappedDatabase=!exact&&!mapped&&(existing.contains(fingerprint(c,semantic,semanticIds.contains(c.getString(c.getColumnIndexOrThrow("segment_id"))),null,"merge:"+namespace))||existing.contains(fingerprint(c,semantic,semanticIds.contains(c.getString(c.getColumnIndexOrThrow("segment_id"))),"merge:"+namespace,"merge:"+namespace)));
                    if(mappedDatabase)mappedOrigins.add(c.getLong(c.getColumnIndexOrThrow("database_id")));
                    if(exact||mapped||mappedDatabase)ids.add(c.getLong(c.getColumnIndexOrThrow("_id")));
                    if(mapped||mappedDatabase){String id=c.getString(c.getColumnIndexOrThrow("segment_id"));mappedDuplicates.put(id,TimelineIdentity.mapped(id,"merge:"+namespace,semanticIds.contains(id)));}
                }
            }
        }
        // A previously rekeyed duplicate can only be removed if no retained row depends on
        // its old identity. Unknown references fail before any aggregate mutation.
        if(!mappedDuplicates.isEmpty()||!mappedOrigins.isEmpty())for(String table:TABLES) {
            String name=table.startsWith("aux")?"aux.db":"odlh.db";
            try(SQLiteDatabase db=TimelineDatabase.open(new File(incoming,name),TimelineDatabase.RO);Cursor c=db.rawQuery("SELECT * FROM "+table,null)) {
                while(c.moveToNext())if(!duplicates.get(table).contains(c.getLong(c.getColumnIndexOrThrow("_id")))) {
                    String id=c.getString(c.getColumnIndexOrThrow("segment_id"));TimelineDatabase.require(!mappedDuplicates.containsKey(id),"timeline_merge_reference_requires_mapping");
                    byte[] original=c.getBlob(c.getColumnIndexOrThrow("semantic_segment"));
                    for(long origin:mappedOrigins){int column=c.getColumnIndex("database_id");TimelineDatabase.require((column<0||c.getLong(column)!=origin)&&!TimelineIdentity.containsOrigin(original,origin),"timeline_merge_origin_reference_requires_mapping");}
                    TimelineDatabase.require(Arrays.equals(original,TimelineIdentity.rewrite(original,id,mappedDuplicates,!table.equals("edited_segment_table"))),"timeline_merge_reference_requires_mapping");
                }
            }
        }
        for(String table:TABLES) {
            String name=table.startsWith("aux")?"aux.db":"odlh.db";
            try(SQLiteDatabase db=TimelineDatabase.open(new File(incoming,name),SQLiteDatabase.OPEN_READWRITE|SQLiteDatabase.NO_LOCALIZED_COLLATORS)) {
                db.beginTransaction();try(SQLiteStatement remove=db.compileStatement("DELETE FROM "+table+" WHERE _id=?")){for(long id:duplicates.get(table)){remove.bindLong(1,id);TimelineDatabase.require(remove.executeUpdateDelete()==1,"timeline_merge_row_missing");}db.setTransactionSuccessful();}finally{db.endTransaction();}
                skipped+=duplicates.get(table).size();
            }
        }
        // A namespace that cannot be a numeric Gaia ID includes every existing identity.
        TimelineIdentity.rekeyConflicts(incoming,new File(aggregate,"odlh.db"),new File(aggregate,"aux.db"),"merge:"+namespace);
        for(String name:new String[]{"odlh.db","aux.db"})try(SQLiteDatabase db=TimelineDatabase.open(new File(aggregate,name),SQLiteDatabase.OPEN_READWRITE|SQLiteDatabase.NO_LOCALIZED_COLLATORS)) {
            db.execSQL("ATTACH DATABASE ? AS incoming",new Object[]{new File(incoming,name).getPath()});
            db.beginTransaction();try {
                for(String table:TABLES) {
                    if(table.startsWith("aux")!=name.equals("aux.db"))continue;
                    StringBuilder columns=new StringBuilder();
                    try(Cursor c=db.rawQuery("PRAGMA main.table_info("+table+")",null)){while(c.moveToNext()){String column=c.getString(1);TimelineDatabase.require(column.matches("[a-z_]+"),"timeline_column_invalid");if(column.equals("_id"))continue;if(columns.length()>0)columns.append(',');columns.append(column);}}
                    db.execSQL("INSERT INTO main."+table+" ("+columns+") SELECT "+columns+" FROM incoming."+table);
                }
                db.setTransactionSuccessful();
            }finally{db.endTransaction();}
        }
        TimelineDatabase.clearImportGeller(aggregate);
        return skipped;
    }
}
