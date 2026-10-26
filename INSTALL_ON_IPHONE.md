# Install KoraVuba on your iPhone from Windows (free, no Mac)

You need your Windows PC, your iPhone and its USB cable, an Apple ID (the
free one you use on the iPhone) and a GitHub account (free).

The app works for **7 days**, then you reinstall it (step 5 again, about 1
minute). Your data on the iPhone stays as long as you don't delete the app.

---

## 0. (Optional) Put your sample data in the app

New installs start from `assets\db\koravuba.db`. To give the iPhone the data
you entered on the emulator, run this inside the project with the emulator
running (close the app on the emulator first):

```powershell
cmd /c "adb exec-out run-as rw.koravuba.app cat databases/koravuba.db > assets\db\koravuba.db"
```

Use `cmd /c` exactly as shown: PowerShell's own `>` would corrupt the
database file.

## 1. Put the project on GitHub

1. Create a repository at <https://github.com/new>, e.g. `koravuba_app`.
2. In PowerShell, inside the project folder:
   ```powershell
   git init
   git add .
   git commit -m "KoraVuba app"
   git branch -M main
   git remote add origin https://github.com/<your-username>/koravuba_app.git
   git push -u origin main
   ```

## 2. Build the iPhone app on Codemagic (free plan)

1. Go to <https://codemagic.io> and **Sign up with GitHub**.
2. **Add application**, choose GitHub, pick `koravuba_app`, project type
   **Flutter App**.
3. Codemagic finds `codemagic.yaml`. Choose the workflow
   **"iPhone app (unsigned IPA for Sideloadly)"** and **Start new build**.
4. Wait about 10–20 minutes. When it is green, download **`KoraVuba-unsigned.ipa`**
   from **Artifacts**.

## 3. Prepare Windows

1. Install **iTunes from apple.com**: <https://www.apple.com/itunes/>. Use the
   website download, not the Microsoft Store version; Sideloadly needs it.
2. Install **Sideloadly**: <https://sideloadly.io>.

## 4. Prepare the iPhone 12

1. Connect it to the PC with the cable, unlock it and tap **Trust This Computer**.
2. After the first install (step 5), turn on **Settings → Privacy & Security →
   Developer Mode → On**. The iPhone restarts; confirm **Turn On**.

## 5. Install

1. Open **Sideloadly**. Your iPhone appears at the top.
2. Drag **`KoraVuba-unsigned.ipa`** into Sideloadly.
3. Type your **Apple ID** e-mail and press **Start**, then enter your Apple ID
   password when asked (and the 2-factor code).
4. When it says **Done**, on the iPhone go to **Settings → General → VPN &
   Device Management →** tap your Apple ID **→ Trust**.
5. Open **KoraVuba**.

**Every 7 days:** connect the iPhone, open Sideloadly, drag the same `.ipa`
and press Start. The app is refreshed and your data stays.

---

### Problems

* **"Untrusted Developer"**: do step 5.4.
* **Developer Mode option missing**: install once with Sideloadly first; the
  option then appears.
* **Codemagic build failed**: open the red step, copy the log and send it to
  your developer.
* **For other people's iPhones, or no 7-day limit**: you need an Apple
  Developer account (99 USD/year) and TestFlight.
