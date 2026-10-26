# Put KoraVuba on GitHub and install it from your phone

Every time you push changes, GitHub builds the Android app by itself
(**Actions** tab, about 6–10 minutes) and publishes it on the **Releases**
page. On your Android phone you open that page, download the `.apk` and
install it. Nothing to install on the phone except the app itself.

> **What gets published:** every APK contains the starting database
> (`assets/db/koravuba.db`). In this repository it holds only the HQ admin
> account, so it is safe to keep the repository **public**: anyone can then
> download the app from the Releases page without a GitHub account. If you
> ever ship real user data in that file, make the repository private.

---

## 1. (Optional) Put your current data in the app

New installs start from `assets\db\koravuba.db`. To ship the data you entered
on the emulator, close the app on the emulator and run this in the project
folder:

```powershell
cmd /c "adb exec-out run-as rw.koravuba.app cat databases/koravuba.db > assets\db\koravuba.db"
```

## 2. Create a signing key once (strongly recommended)

Android only lets you **update** an installed app if every version is signed
with the same key. Without your own key GitHub signs each build with a
different temporary key, so every update would need an uninstall, which
erases the data on the phone.

In PowerShell (outside the project folder, e.g. in Documents):

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Choose a password and remember it. Answer the questions (name, city: Kigali,
country code: RW) and confirm with `yes`.

Copy the key as text to the clipboard:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Clipboard
```

**Keep `upload-keystore.jks` and the password safe.** Never put them in the
project folder. If you lose them you cannot update the app any more.

## 3. Create the GitHub repository and push

1. Create a **public** repository at <https://github.com/new>, named
   `koravuba_app`, with no README.
2. Repository → **Settings → Secrets and variables → Actions → New repository
   secret**. Add these four:

   | Name | Value |
   |---|---|
   | `ANDROID_KEYSTORE_BASE64` | paste (Ctrl+V) the text from step 2 |
   | `ANDROID_KEYSTORE_PASSWORD` | your keystore password |
   | `ANDROID_KEY_ALIAS` | `upload` |
   | `ANDROID_KEY_PASSWORD` | the same password |

3. In PowerShell inside the project folder (install Git from
   <https://git-scm.com> if `git` is unknown):

   ```powershell
   git init
   git add .
   git commit -m "KoraVuba app"
   git branch -M main
   git remote add origin https://github.com/<your-username>/koravuba_app.git
   git push -u origin main
   ```

4. Open the repository → **Actions** tab. **Android APK** is running. Wait for
   the green ✔.

## 4. Install on your Android phone

1. On the phone, open the browser.
2. Go to `github.com/<your-username>/koravuba_app/releases`.
3. Under the newest **KoraVuba Android build**, tap **KoraVuba-N.apk**.
4. Open the downloaded file. If asked, allow **Install unknown apps** for your
   browser, then tap **Install**.

**To update later:** change the code, then run
`git add . ; git commit -m "update" ; git push`. Wait for the build, then
download and install the new APK over the old one. With the signing key from
step 2, your data on the phone stays.

> The very first time you switch from an APK built without the key (or from
> `flutter run`) to one built with it, Android may say "App not installed".
> Uninstall once, then install. Every update after that works normally.

## 5. iPhone

Every push also builds the iPhone app (**iPhone IPA (unsigned)** in Actions).
When it is green, download the `.ipa` from **Releases** on your **PC** and install it with
Sideloadly (see `INSTALL_ON_IPHONE.md`). An iPhone cannot install it directly
from the browser; Apple does not allow that.

Builds are free and unlimited on public repositories.
