package com.xayah.dex;

import android.content.ContentResolver;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.IContentProvider;
import android.os.Binder;

public final class FakeContext extends ContextWrapper {
    private final boolean shellIdentity;
    private final int providerUserId;
    private final boolean strictProviderUser;
    // External references are held once per authority for this short-lived CLI.
    // Binder death releases them when app_process exits; do not acquire one per row.
    private final java.util.Map<String,IContentProvider> providers=new java.util.HashMap<>();
    private synchronized IContentProvider provider(String name) {
        if(name.indexOf('@')>=0) {
            int split=name.indexOf('@');
            if(Integer.parseInt(name.substring(0,split))!=providerUserId)throw new SecurityException("PROVIDER_USER_MISMATCH");
            name=name.substring(split+1);
        }
        IContentProvider p=providers.get(name);
        if(p==null) { p=HiddenApiHelper.getContentProviderExternal(name,new Binder(),providerUserId,strictProviderUser); if(p!=null)providers.put(name,p);
            if("1".equals(System.getenv("TELEPHONY_DEBUG")))System.err.println("PROVIDER_ACQUIRE user="+providerUserId+" found="+(p!=null));
        }
        return p;
    }
    public FakeContext(Context base) {
        this(base, false);
    }
    public FakeContext(Context base, boolean shellIdentity) {
        this(base,shellIdentity,0,false);
    }
    public FakeContext(Context base, boolean shellIdentity, int userId, boolean strictUser) {
        super(base);
        this.shellIdentity=shellIdentity;
        this.providerUserId=userId;
        this.strictProviderUser=strictUser;
        this.contentResolver=createResolver();
    }
    @androidx.annotation.Keep
    public int getUserId() { return providerUserId; }

    @Override public String getOpPackageName() {
        return shellIdentity ? (android.os.Process.myUid()==0 ? "root" : "com.android.shell") : super.getOpPackageName();
    }
    @Override public android.content.AttributionSource getAttributionSource() {
        if(shellIdentity)return new android.content.AttributionSource.Builder(android.os.Process.myUid())
                .setPackageName(getOpPackageName()).build();
        return super.getAttributionSource();
    }

    private final ContentResolver contentResolver;
    private ContentResolver createResolver() { return new ContentResolver(this) {
        @SuppressWarnings({"unused", "ProtectedMemberInFinalClass"})
        // @Override (but super-class method not visible)
        protected IContentProvider acquireProvider(Context c, String name) {
            return provider(name);
        }

        @SuppressWarnings("unused")
        // @Override (but super-class method not visible)
        public boolean releaseProvider(IContentProvider icp) {
            return false;
        }

        @SuppressWarnings({"unused", "ProtectedMemberInFinalClass"})
        // @Override (but super-class method not visible)
        protected IContentProvider acquireUnstableProvider(Context c, String name) {
            return provider(name);
        }

        @SuppressWarnings("unused")
        // @Override (but super-class method not visible)
        public boolean releaseUnstableProvider(IContentProvider icp) {
            return false;
        }

        @SuppressWarnings("unused")
        // @Override (but super-class method not visible)
        public void unstableProviderDied(IContentProvider icp) {
            // ignore
        }
    }; }

    @Override
    public ContentResolver getContentResolver() {
        return contentResolver;
    }
}

// https://github.com/Genymobile/scrcpy/blob/91373d906b100349de959f49172d4605f66f64b2/server/src/main/java/com/genymobile/scrcpy/FakeContext.java
