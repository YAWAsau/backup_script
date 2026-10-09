package com.xayah.dex;

import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/** Local account identity and display labels only. Never reads passwords or auth tokens. */
final class GoogleAccountNames {
    static final class Account {
        final String selector, gaia, label;
        Account(String email, String gaia, String label) throws Exception {
            selector=TimelineDatabase.digest(("portable_geller_"+email+".db").getBytes(StandardCharsets.UTF_8));
            this.gaia=gaia; this.label=clean(label);
        }
        Account(org.json.JSONObject saved) throws Exception {
            selector=saved.getString("selector"); gaia=saved.getString("gaia"); label=clean(saved.getString("label"));
            TimelineDatabase.require(selector.matches("[a-f0-9]{64}")&&gaia.matches("[0-9]+"),"account_cache_invalid");
        }
    }
    static String clean(String value) {
        if(value==null)return "";
        StringBuilder out=new StringBuilder();
        value.codePoints().limit(100).forEach(c->{
            if(!Character.isISOControl(c) && Character.getType(c)!=Character.FORMAT)out.appendCodePoint(c);
        });
        return out.toString().trim();
    }
    static List<Account> read(int user) throws Exception {
        return read(user,false);
    }
    private static List<Account> read(int user,boolean fresh) throws Exception {
        TimelineDatabase.require(user>=0&&user<=1000,"user_invalid");
        List<Account> result=new ArrayList<>();
        if(!new File("/data/user/"+user+"/com.google.android.gms").isDirectory())return result;
        File file=new File("/data/system_ce/"+user+"/accounts_ce.db");
        if(!file.isFile())return result;
        return GoogleAccountCache.read(file,new File("/data/.speedbackup_account_names"),user,fresh);
    }
    // Only called with an owned private copy, never with the system account database.
    static List<Account> queryCopy(File file) throws Exception {
        List<Account> result=new ArrayList<>();
        try(SQLiteDatabase db=TimelineDatabase.open(file,SQLiteDatabase.OPEN_READWRITE|SQLiteDatabase.NO_LOCALIZED_COLLATORS)) {
            TimelineDatabase.require("ok".equals(TimelineDatabase.scalar(db,"PRAGMA quick_check")),"account_copy_invalid");
        try(
            Cursor c=db.rawQuery("SELECT a.name,g.value,coalesce(f.value,''),coalesce(l.value,'') FROM accounts a JOIN extras g ON g.accounts_id=a._id AND g.key='GoogleUserId' LEFT JOIN extras f ON f.accounts_id=a._id AND f.key='firstName' LEFT JOIN extras l ON l.accounts_id=a._id AND l.key='lastName' WHERE a.type='com.google' ORDER BY a._id",null)) {
            while(c.moveToNext()) {
                String email=c.getString(0),gaia=c.getString(1),given=clean(c.getString(2)),family=clean(c.getString(3));
                if(email==null||email.contains("/")||email.contains("\\")||gaia==null||!gaia.matches("[0-9]+"))continue;
                String label=(given+family).matches("[\\p{IsHan}]+")?family+given:(given+" "+family).trim();
                result.add(new Account(email,gaia,label));
            }
        }
        }
        return result;
    }
    static Account select(int user,String selector) throws Exception {
        // A display cache must never authorize backup/restore account binding.
        List<Account> accounts=read(user,true); Account found=null;
        for(Account account:accounts)if(selector==null||selector.isEmpty()||selector.equals(account.selector)) {
            TimelineDatabase.require(found==null,"timeline_target_account_required"); found=account;
        }
        TimelineDatabase.require(found!=null,"timeline_target_account_unavailable");return found;
    }
    static Account history(int user) throws Exception {
        List<Account> accounts=histories(user);
        TimelineDatabase.require(accounts.size()==1,"timeline_source_account_ambiguous");return accounts.get(0);
    }
    static List<Account> histories(int user) throws Exception {
        List<Account> known=read(user),result=new ArrayList<>();
        for(String name:new String[]{"odlh-storage.db","aux-odlh-storage.db"}) {
        File file=new File("/data/user/"+user+"/com.google.android.gms/databases/"+name);
        if(name.startsWith("aux") && TimelineDatabase.missing(file))continue;
        String query=name.startsWith("aux")?"SELECT DISTINCT obfuscated_gaia_id FROM aux_semantic_segment_table":"SELECT obfuscated_gaia_id FROM semantic_segment_table UNION SELECT obfuscated_gaia_id FROM edited_segment_table";
        try(SQLiteDatabase db=TimelineDatabase.open(file,TimelineDatabase.RO); Cursor rows=db.rawQuery(query,null)) {
            while(rows.moveToNext()){
                String id=rows.getString(0);Account found=null;
                for(Account a:known)if(a.gaia.equals(id)){TimelineDatabase.require(found==null,"timeline_source_account_ambiguous");found=a;}
                TimelineDatabase.require(found!=null,"timeline_source_account_unavailable");if(!result.contains(found))result.add(found);
            }
        }finally{TimelineDatabase.fixSidecars(file);}
        }
        TimelineDatabase.require(result.size()<=32,"timeline_collection_count_invalid");return result;
    }
    static String label(Account a) { return a.label.isEmpty()?"Google 帳號（"+a.selector.substring(0,8)+"）":a.label; }
    static String sourceLabel(int user,File input,org.json.JSONObject manifest)throws Exception {
        String saved=clean(manifest.optString("source_display_name",""));
        if(!saved.isEmpty())return saved;
        String gaia=TimelineDatabase.rowAccount(new File(input,"odlh.db"),"semantic_segment_table");
        for(Account a:read(user))if(a.gaia.equals(gaia))return label(a);
        return "來源帳號名稱未知";
    }
    static String fields(int user)throws Exception {
        StringBuilder out=new StringBuilder();
        for(Account a:read(user))out.append(a.selector).append('\t').append(label(a)).append('\n');
        return out.toString();
    }
    static String greeting(int user) {
        try {
            List<Account> accounts=read(user);StringBuilder names=new StringBuilder();int count=0;
            for(Account a:accounts)if(!a.label.isEmpty()) {
                if(count++>=2){names.append(" 等");break;}
                if(names.length()>0)names.append("、");names.append(a.label);
            }
            if(names.length()==0)return "";
            return accounts.size()==1?"歡迎回來，"+names+"！\n":"歡迎回來！已登入 Google 帳號："+names+"\n";
        } catch(Exception ignored) { return ""; }
    }
}
