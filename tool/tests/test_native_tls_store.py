"""JVM checks of CA export logic; Android trust/AtomicFile behavior needs device tests."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'packages/media_kit_libs_android_audio/android/src/main/java/com/alexmercerind/media_kit_libs_android_audio/TrustedCaStore.java'
STUBS = {
    'android/content/Context.java': '''package android.content;
public abstract class Context { public abstract java.io.File getNoBackupFilesDir(); }
''',
    'android/util/Base64.java': '''package android.util;
public class Base64 {
  public static final int NO_WRAP = 2;
  public static String encodeToString(byte[] bytes, int flags) {
    return java.util.Base64.getEncoder().encodeToString(bytes);
  }
}
''',
    'android/util/AtomicFile.java': '''package android.util;
import java.io.*;
import java.nio.file.*;
public class AtomicFile {
  public static boolean failWrite;
  private final File base, next;
  public AtomicFile(File file) { base = file; next = new File(file + ".new"); }
  public FileOutputStream startWrite() throws IOException {
    base.getParentFile().mkdirs();
    return new FileOutputStream(next) {
      public void write(byte[] bytes) throws IOException {
        if (failWrite) { super.write(bytes, 0, Math.min(10, bytes.length)); throw new IOException("fixture write failed"); }
        super.write(bytes);
      }
    };
  }
  public void finishWrite(FileOutputStream stream) {
    try { stream.close(); Files.move(next.toPath(), base.toPath(), StandardCopyOption.REPLACE_EXISTING); }
    catch (IOException e) { throw new RuntimeException(e); }
  }
  public void failWrite(FileOutputStream stream) {
    try { stream.close(); } catch (IOException ignored) {}
    next.delete();
  }
}
''',
    'com/alexmercerind/media_kit_libs_android_audio/TrustedCaHarness.java': '''package com.alexmercerind.media_kit_libs_android_audio;
import android.content.Context;
import android.util.AtomicFile;
import java.io.*;
import java.nio.file.*;
import java.security.*;
import java.security.cert.*;
import javax.net.ssl.*;
import java.util.*;
public class TrustedCaHarness {
  public static void main(String[] args) throws Exception {
    final File directory = new File(args[1]);
    Context context = new Context() { public File getNoBackupFilesDir() { return directory; } };
    if (args[0].equals("empty")) {
      try { TrustedCaStore.writeCertificates(context, new X509Certificate[0]); throw new AssertionError("empty trust store accepted"); }
      catch (GeneralSecurityException expected) {}
      if (directory.exists() && directory.list().length != 0) throw new AssertionError("empty export wrote a file");
      return;
    }
    File exported = TrustedCaStore.write(context);
    if (!exported.isAbsolute() || !exported.getParentFile().equals(directory)) throw new AssertionError("wrong storage path");
    byte[] original = Files.readAllBytes(exported.toPath());
    try (InputStream input = new FileInputStream(exported)) {
      Collection<? extends java.security.cert.Certificate> certificates = CertificateFactory.getInstance("X.509").generateCertificates(input);
      if (certificates.isEmpty()) throw new AssertionError("unparseable/empty PEM output");
    }
    if (args[0].equals("rollback")) {
      AtomicFile.failWrite = true;
      try { TrustedCaStore.write(context); throw new AssertionError("write failure ignored"); }
      catch (IOException expected) {}
      if (!Arrays.equals(original, Files.readAllBytes(exported.toPath()))) throw new AssertionError("previous CA snapshot was damaged");
      if (new File(exported + ".new").exists()) throw new AssertionError("partial output remained");
    } else if (args[0].equals("refresh")) {
      Files.write(exported.toPath(), "stale snapshot".getBytes());
      File refreshed = TrustedCaStore.write(context);
      if (!Arrays.equals(original, Files.readAllBytes(refreshed.toPath()))) throw new AssertionError("CA export did not replace stale contents");
    }
  }
}
''',
}


class NativeTlsStoreTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.java_home = Path(os.environ.get('JAVA_HOME', ROOT.parent / '.android-toolchain/jdk/amazon-corretto-17.jdk/Contents/Home'))
        if not (cls.java_home / 'bin/javac').is_file():
            raise unittest.SkipTest('Set JAVA_HOME to a JDK to run native TLS export checks')

    def run_case(self, case):
        self.assertTrue(SOURCE.is_file(), 'Android trusted CA export has not been implemented')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            sources = []
            for name, content in STUBS.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
                sources.append(str(path))
            compiled = root / 'classes'
            compiled.mkdir()
            compile_result = subprocess.run([str(self.java_home / 'bin/javac'), '-d', str(compiled), *sources, str(SOURCE)], text=True, capture_output=True)
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            result = subprocess.run([str(self.java_home / 'bin/java'), '-cp', str(compiled), 'com.alexmercerind.media_kit_libs_android_audio.TrustedCaHarness', case, str(root / 'no_backup')], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_exports_parseable_default_trust_anchors_to_no_backup_directory(self):
        self.run_case('export')

    def test_empty_trust_anchor_list_fails_without_writing(self):
        self.run_case('empty')

    def test_failed_write_preserves_previous_complete_snapshot(self):
        self.run_case('rollback')

    def test_refresh_replaces_existing_snapshot_instead_of_appending(self):
        self.run_case('refresh')


if __name__ == '__main__':
    unittest.main()
