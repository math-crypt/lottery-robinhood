# 🚀 Guide de Lancement $IRL (Mainnet)

Ce document récapitule les étapes exactes pour lancer le projet On-Chain et configurer le bot Telegram le Jour J.

---

## 1. Déploiement des Contrats (Smart Contracts)

Le script `script/DeployLotteryEcosystem.s.sol` s'occupe de tout déployer d'un seul coup. Voici comment l'utiliser :

### Étape 1 : Préparation
- Mets ton `PRIVATE_KEY` dans le fichier `.env` (celui du wallet dev qui va payer les frais de gaz et recevoir le Supply initial).
- Le script crée automatiquement le Token, le NFT, le Staking et le **Hook**. 
- Il initialise ensuite la Pool Uniswap V4 avec un prix mathématique correspondant à un **Market Cap de 20k$** (cf. les constantes `SQRT_PRICE_IRL` dans le fichier).

### Étape 2 : L'Anti-Whale Automatique
L'Anti-Whale est **activé par défaut** au déploiement (`limitsEnabled = true`).
Pour configurer la levée automatique à 40k$ de Market Cap :
1. Une fois déployé, va sur l'Explorer de la blockchain (ex: Robinhood Scan).
2. Connecte ton wallet Dev sur la page du **Hook Contract**.
3. Cherche la fonction `setDisableAntiWhalePrice(...)`.
4. Rentre la valeur mathématique (`sqrtPriceX96`) qui correspond à ton 40k MC. *(Astuce: Si ton token0 est l'ETH, il suffit de calculer le prix x2 ou x0.5 selon le sens de la paire. On pourra faire le calcul exact le jour J selon le prix de l'ETH).*

---

## 2. Configuration du Bot Telegram (Jour J)

Le Bot est très simple à démarrer. Voici la marche à suivre :

### Les Variables d'Environnement (Fichier `.env` dans le dossier `bot/`)
Avant de lancer le bot, tu devras remplir ces trois variables essentielles :
```env
# Ton token BotFather
BOT_TOKEN=8938455205:AAERTGurAdLIA_MjMCM0Q5qEzrlQLfW-s44

# L'adresse de ton Hook déployé (pour qu'il lise les cagnottes On-Chain)
HOOK_CONTRACT_ADDRESS=0xTonAdresseDeHookIci

# L'URL du nœud RPC de ta blockchain (ex: Alchemy, Infura, ou le RPC public de Robinhood Chain)
RPC_URL=https://rpc.robinhoodchain.com
```

### Le Lancement
Sur ton serveur (ou ton PC si tu l'héberges chez toi), ouvre un terminal dans le dossier `bot/` et lance :
```bash
npm install   # Installe les dépendances (ethers, telegraf)
node index.js # Lance le bot en production
```
*(Pour qu'il tourne H24 sur un serveur, on utilisera un outil comme `pm2` : `pm2 start index.js --name irl-bot`)*.

### Mise à jour post-lancement (Quand l'Anti-Whale saute)
Le jour où l'anti-whale se désactive (à 40k), l'idéal est de changer la phrase dans le code du bot `index.js` :
- Ancienne phrase : "*These limits automatically disable once the Market Cap reaches $40k*"
- Nouvelle phrase : "*✅ 40k Market Cap Reached: The limits are officially DISABLED. Whales are free to swim!*"
Il te suffira de modifier le texte dans le code, puis de redémarrer le bot.

---

## 3. Le Logo (On-Chain & Telegram)

Je viens de te générer un logo parfait pour le projet ! (Regarde l'image envoyée juste au-dessus).
- **Pour Telegram :** Utilise l'image générée comme photo de profil de ton Bot (`@BotFather` > `/setuserpic`) et de ton Groupe Telegram.
- **Pour le Token On-Chain :** Lorsque tu vérifieras le contrat sur Robinhood Scan, tu pourras y lier ton logo. S'ils demandent une URL, tu pourras uploader l'image sur GitHub ou Imgur.
