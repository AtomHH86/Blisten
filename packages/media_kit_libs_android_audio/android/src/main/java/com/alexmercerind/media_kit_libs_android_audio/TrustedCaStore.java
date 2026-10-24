package com.alexmercerind.media_kit_libs_android_audio;

import android.content.Context;
import android.util.AtomicFile;
import android.util.Base64;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyStore;
import java.security.cert.X509Certificate;

import javax.net.ssl.TrustManager;
import javax.net.ssl.TrustManagerFactory;
import javax.net.ssl.X509TrustManager;

/** Supplies the native TLS backend with a snapshot of Android's default trust anchors. */
final class TrustedCaStore {
    private TrustedCaStore() {}

    static File write(Context context) throws GeneralSecurityException, IOException {
        TrustManagerFactory factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        factory.init((KeyStore) null);
        for (TrustManager manager : factory.getTrustManagers()) {
            if (manager instanceof X509TrustManager) {
                return writeCertificates(context, ((X509TrustManager) manager).getAcceptedIssuers());
            }
        }
        throw new GeneralSecurityException("Android default X509 trust manager is unavailable");
    }

    // Serialized across Flutter engines: consumers must never receive a partially written PEM file.
    static synchronized File writeCertificates(Context context, X509Certificate[] certificates)
            throws GeneralSecurityException, IOException {
        if (certificates == null || certificates.length == 0) {
            throw new GeneralSecurityException("Android default trust anchor list is empty");
        }
        File directory = context.getNoBackupFilesDir();
        if (directory == null) {
            throw new IOException("Application no-backup directory is unavailable");
        }
        File destination = new File(directory, "blisten_trusted_cas.pem");
        AtomicFile atomic = new AtomicFile(destination);
        FileOutputStream stream = null;
        try {
            stream = atomic.startWrite();
            for (X509Certificate certificate : certificates) {
                String encoded = Base64.encodeToString(certificate.getEncoded(), Base64.NO_WRAP);
                StringBuilder pem = new StringBuilder("-----BEGIN CERTIFICATE-----\n");
                for (int offset = 0; offset < encoded.length(); offset += 64) {
                    pem.append(encoded, offset, Math.min(offset + 64, encoded.length())).append('\n');
                }
                pem.append("-----END CERTIFICATE-----\n");
                stream.write(pem.toString().getBytes(StandardCharsets.US_ASCII));
            }
            atomic.finishWrite(stream);
            stream = null;
        } finally {
            if (stream != null) {
                atomic.failWrite(stream);
            }
        }
        if (!destination.isFile() || destination.length() == 0) {
            throw new IOException("Android trusted CA export is unavailable");
        }
        return destination.getAbsoluteFile();
    }
}
