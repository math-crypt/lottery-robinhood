# Règles Spécifiques - Projet Lottery Robinhood

## 📜 Contexte du Projet
Nous développons un contrat token sur le thème "Lottery Robinhood". Les mécanismes impliqueront probablement une loterie intégrée et une redistribution (façon Robin des Bois).

## 🤖 Règles de Suivi de Développement (CRITIQUE)
Afin de pouvoir reprendre le développement facilement lors de futures sessions et de maintenir l'intégrité du projet, tu **DOIS ABSOLUMENT** respecter le flux de travail suivant :

1. **Au début de chaque session ou avant de coder :**
   - Lis **TOUJOURS** `AUDIT_PLAN.md` à la racine pour comprendre l'état d'avancement et la phase en cours.
   - Lis `CHANGELOG.md` pour prendre connaissance des dernières modifications effectuées.
   - Demande à l'utilisateur sur quelle phase ou tâche spécifique on travaille si ce n'est pas précisé dans son prompt.

2. **Pendant le développement :**
   - Ne travaille et ne modifie **QUE** la portée (scope) demandée par l'utilisateur.
   - Si tu identifies un bug, une amélioration, ou un problème dans un fichier hors de ton scope actuel, **ne le modifie pas**. Note-le immédiatement dans `BACKLOG.md` sous la section "Trouvé pendant l'audit / le développement" et reprends ta tâche principale.

3. **À la fin de chaque tâche ou session :**
   - Coche les tâches accomplies dans `AUDIT_PLAN.md` (remplace `[ ]` par `[x]`).
   - Mets à jour la section **"Journal de Session"** à la fin de `AUDIT_PLAN.md`. Ajoutes-y la date et un résumé de ce qui a été fait, ce qui a été trouvé (backlog), et ce qui bloque éventuellement pour la prochaine fois.
   - Mets à jour `CHANGELOG.md` sous la section `## [Unreleased]` avec toutes les modifications techniques, de code ou d'architecture.

Ne pars jamais sur une tâche non demandée, même si elle te paraît "rapide" ou "évidente".

## 🏗️ Architecture et Contraintes
1. **Interface Utilisateur :**
   - **IL N'Y A PAS DE FRONT-END.** L'interaction se fait *exclusivement* via le **Bot Telegram**.
   - Ne propose jamais de développer ou de modifier un site web / dApp frontend. Concentre-toi uniquement sur les smart contracts et le bot Telegram (dossier `bot/`).
2. **Gestion de Version (GitHub) :**
   - Lors d'un commit ou d'un push, **ne mets que les fichiers utiles en production**.
   - **EXCLURE** catégoriquement les dossiers de tests (`test/`), les scripts de simulation inutiles en prod, ou tout autre fichier de dev local. Utilise `.gitignore` ou sois sélectif dans tes commandes `git add`.
