# BL-SE-03 · No plaintext key or secret files lying around

**Why:** Certificates, cloud keys and `.env` files left in Downloads, on the Desktop or in your home folder are the first thing a stealer sweeps up.

**Real attack:** Trend Micro's 2025 analysis of the AMOS stealer shows it collecting files with extensions such as txt, pdf, docx, wallet, key, json and db from Desktop, Documents and Downloads, zipping them and uploading them. ([source](https://www.trendmicro.com/en_gb/research/25/i/an-mdr-analysis-of-the-amos-stealer-campaign.html))

**Check it yourself:** in the Terminal app, this lists the same file names the check looks for:

    find ~/Downloads ~/Desktop ~/Documents -maxdepth 4 -type f \( -iname '*.pem' -o -iname '*.key' -o -iname '*.p12' -o -iname '*.pfx' -o -name credentials -o -name credentials.json -o -iname 'sa-key*.json' -o -name id_rsa -o -name id_ecdsa -o -name id_ed25519 -o -name id_dsa \)

The check also looks at the top of your home folder, and for `.env` files at the top of your home, Downloads and Desktop. A `.pem` or `.key` file counts only if it holds a private key (it contains `PRIVATE KEY`), so certificates and Keynote documents don't.

**How to fix:** move each one into your password manager (as a document or an SSH key) and delete it, or delete it if it's no longer needed. A `.env` inside a project folder is normal; one at the top of your home, Downloads or Desktop isn't.

**What the agent is doing:** looking for these file names in four places only (never inside folders you marked private), and searching a `.pem` or `.key` file for the words that mark a private key, never printing what's in it. The first time, macOS may ask whether your terminal or agent app may open Desktop, Documents or Downloads. Allowing it lets the check finish; if you decline, it reports ERROR for that folder.
