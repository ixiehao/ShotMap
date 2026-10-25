# ShotMap

[![Dernière version](https://img.shields.io/github/v/release/ixiehao/ShotMap?display_name=tag&label=release&color=2563eb)](https://github.com/ixiehao/ShotMap/releases/latest)
[![Vérification](https://img.shields.io/github/actions/workflow/status/ixiehao/ShotMap/ci.yml?branch=main&label=verify)](https://github.com/ixiehao/ShotMap/actions/workflows/ci.yml)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111827?logo=apple)](https://github.com/ixiehao/ShotMap/releases/latest)
[![Licence MIT](https://img.shields.io/badge/license-MIT-059669)](LICENSE)

[English](README.md) · [简体中文](README.zh-CN.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [Español](README.es.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

**L’application est disponible en 7 langues :** English · 简体中文 · Français · Русский · Español · 日本語 · 한국어. Toutes sont incluses dans un seul téléchargement.

![Interface anglaise de ShotMap créant une planche d’images à partir de Tears of Steel](website/assets/workspace-en.webp?v=20261017)

*L’exemple ci-dessus montre l’interface en anglais. L’application est aussi disponible en français.*

## Vos vidéos, faciles à retrouver.

Un dossier peut contenir des années de souvenirs : famille, voyages, petits moments du quotidien. Mais un nom de fichier ou une miniature suffit rarement à retrouver la bonne vidéo. **ShotMap** réunit des moments de chaque vidéo sur une planche d’images, pour repérer les scènes sans ouvrir tous les fichiers un à un.

Commencez par **Sélection auto**, puis remplacez les images de votre choix dans **Choisir les images**. ShotMap est une application macOS native et open source. Le traitement et l’export se font sur votre Mac, sans compte ni envoi de vidéos en ligne.

> **Pour commencer :** [Télécharger la dernière version internationale](https://github.com/ixiehao/ShotMap/releases/latest) · DMG universel · macOS 13 ou ultérieur · Apple Silicon et Intel

> **Vidéo de démonstration :** *Tears of Steel* (2012) © Blender Foundation / Blender Institute, sous licence [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). Les captures et l’animation utilisent cette vidéo.

## Pour les moments que vous voulez retrouver

- **Souvenirs personnels et familiaux :** retrouvez un anniversaire, un voyage, un coucher de soleil ou les premiers pas d’un enfant sans ouvrir chaque fichier.
- **Création et montage :** parcourez un lot de vidéos avant de choisir les séquences à importer dans votre logiciel de montage.
- **Classement des vidéos :** conservez une planche d’images dans le dossier de chaque vidéo, avec les timecodes et le nom du fichier si vous le souhaitez.

## De la vidéo à la planche en trois étapes

| 1. Ajoutez des vidéos | 2. Choisissez les images | 3. Enregistrez la planche |
| --- | --- | --- |
| Glissez une vidéo ou plusieurs à la fois. | Utilisez Sélection auto, puis ajustez les images à la main. | Exportez un PNG ou un JPG dans le dossier de la vidéo. |

## Choisissez vos images et leur présentation

- Privilégie autant que possible des images nettes et variées, en limitant les écrans noirs, le flou et les images presque identiques.
- Réunit lecteur, chronologie, déplacement image par image et galerie dans **Choisir les images**.
- Traite plusieurs vidéos à la suite, permet une pause après la vidéo en cours puis une reprise, et remplit l’aperçu au fur et à mesure.
- Propose des grilles de 3 × 3 à 8 × 8, les proportions, la couleur du fond, la largeur de l’image, les timecodes et le nom du fichier.
- Prend en charge MP4, MOV, MPEG et les autres formats vidéo compatibles avec macOS.
- Permet de changer de langue sans redémarrer, parmi sept langues. L’apparence peut être claire, sombre ou suivre le système.

### Voir l’application en action

Cet enregistrement montre le passage d’une planche terminée au choix manuel des images. La chronologie permet de retrouver un moment, puis la galerie de choisir une autre image avant d’enregistrer.

![ShotMap passe de la planche Tears of Steel au choix manuel des images, avec chronologie et galerie](docs/assets/video-to-storyboard-demo.gif?v=tears-20261016)

## Télécharger et installer

Ouvrez la page de la [dernière version internationale](https://github.com/ixiehao/ShotMap/releases/latest), téléchargez le `.dmg` universel et glissez **ShotMap.app** dans **Applications**. Le même fichier d’installation comprend les sept langues et fonctionne sur les Mac Apple Silicon et Intel.

La page de version fournit une somme de contrôle SHA-256 pour vérifier le téléchargement. ShotMap n’est pas encore notarié par Apple. Si macOS demande de confirmer le développeur, faites un clic avec la touche Control enfoncée sur l’application dans Applications, choisissez **Ouvrir**, puis confirmez avec **Ouvrir**. Il n’est pas nécessaire de réduire les protections de sécurité du système.

### Choisir la langue

Utilisez le menu de langue en haut à droite pour changer immédiatement, sans redémarrer ni vider la file de vidéos. Au premier lancement, ShotMap utilise la langue du système si elle est prise en charge, sinon l’anglais. Il mémorise ensuite votre choix.

## Vos vidéos restent privées

Vos vidéos restent sur votre Mac. ShotMap ne nécessite aucun compte et n’intègre ni suivi, ni envoi vers le cloud, ni moteur Electron, FFmpeg ou Python. La recherche facultative de mises à jour consulte uniquement les informations publiques des versions sur GitHub ; elle n’envoie ni vidéos ni données d’utilisation.

## Aide, retours et communauté

- **Vous découvrez ShotMap ?** Le [site officiel](https://ixiehao.github.io/ShotMap/fr/) présente l’application et ses captures réelles.
- **Besoin d’aide, un problème ou une suggestion ?** Consultez [l’aide](SUPPORT.md), puis utilisez un [formulaire de signalement](https://github.com/ixiehao/ShotMap/issues/new/choose) pour les problèmes reproductibles et les demandes de fonctions précises.
- **Une question ou une expérience à partager ?** Rejoignez [GitHub Discussions](https://github.com/ixiehao/ShotMap/discussions).
- **Envie de contribuer ?** Lisez [CONTRIBUTING.md](CONTRIBUTING.md). Signalez les failles de sécurité par le [canal privé](https://github.com/ixiehao/ShotMap/security/advisories/new).
- **Informations sur le projet :** [CHANGELOG.md](CHANGELOG.md) · [PRIVACY.md](PRIVACY.md) · [Développeur : ixiehao](https://github.com/ixiehao)

## Droits et licences

- Le code Swift, la documentation et l’icône Iris sont des créations originales du projet, publiées sous [licence MIT](LICENSE).
- L’application utilise uniquement les frameworks des SDK Apple. Elle n’intègre aucun code d’application tiers, paquet logiciel, SDK d’analyse ou élément de MoviePrint.
- Les SVG [Tabler Icons Outline](https://github.com/tabler/tabler-icons) sont utilisés sans modification sous [licence MIT](ThirdPartyLicenses/TablerIcons-MIT.txt). La police Noto Sans CJK fournie est sous [SIL Open Font License 1.1](ThirdPartyLicenses/NotoSansCJK-OFL-1.1.txt). Voir [NOTICE.md](NOTICE.md).
- La vidéo de démonstration est *Tears of Steel* (2012) © Blender Foundation / Blender Institute, sous licence [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/).
- Traitez uniquement les vidéos que vous possédez ou êtes autorisé à analyser. Créer une planche ne donne aucun droit de publier ou de redistribuer la vidéo d’origine.

## Documentation de développement

[Index](docs/README.md) · [Développement et validation](docs/DEVELOPMENT.md) · [Maintenance du site](docs/WEBSITE.md).

Le code du site officiel se trouve dans `website/` ; `docs/` contient la documentation de maintenance.
