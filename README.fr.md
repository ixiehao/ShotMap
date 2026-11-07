<p><img src="website/assets/app-icon.png?v=20261101-release017" width="72" height="72" alt="ShotMap" /></p>

# ShotMap

[![Dernière version](https://img.shields.io/github/v/release/ixiehao/ShotMap?display_name=tag&label=release&color=2563eb)](https://github.com/ixiehao/ShotMap/releases/latest)
[![Vérification](https://img.shields.io/github/actions/workflow/status/ixiehao/ShotMap/ci.yml?branch=main&label=verify)](https://github.com/ixiehao/ShotMap/actions/workflows/ci.yml)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111827?logo=apple)](https://github.com/ixiehao/ShotMap/releases/latest)
[![Licence MIT](https://img.shields.io/badge/license-MIT-059669)](LICENSE)

[English](README.md) · [简体中文](README.zh-CN.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [Español](README.es.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

**L’application est disponible en 7 langues :** English · 简体中文 · Français · Русский · Español · 日本語 · 한국어. Toutes sont incluses dans un seul téléchargement.

![ShotMap en français crée une planche à partir de Tears of Steel](website/assets/workspace-fr.webp?v=20261101-release017)

*L’exemple ci-dessus montre l’interface en anglais. L’application est aussi disponible en français.*

## Les scènes de vos vidéos, réunies en une image.

**ShotMap** est une application Mac gratuite et open source qui rassemble les scènes d’une vidéo sur une planche d’images. Parcourez vos souvenirs de famille, vos voyages ou vos rushes sans ouvrir chaque fichier ni parcourir sa barre de lecture.

Commencez par la sélection automatique, puis remplacez ou ajustez chaque image dans la chronologie. Ajoutez plusieurs vidéos pour les traiter par lot et exportez des PNG ou JPG dans le dossier des originaux. Tout se fait sur votre Mac, sans compte ni envoi de vidéos en ligne.

> **Pour commencer :** [Télécharger la dernière version internationale](https://github.com/ixiehao/ShotMap/releases/latest) · DMG Apple Silicon / Intel · macOS 13 ou ultérieur · Apple Silicon et Intel

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

- **Une première sélection automatique :** privilégie les images nettes et variées, en cherchant à limiter les écrans noirs, le flou et les images presque identiques.
- **Vous gardez le dernier mot :** utilisez le lecteur, la chronologie et le déplacement image par image. La sélection automatique conserve vos choix et complète les emplacements restants.
- **Plusieurs vidéos à la suite :** traitez un lot, voyez l’aperçu se remplir et faites une pause après la vidéo en cours.
- **Des images faciles à consulter et à partager :** exportez en PNG ou JPG, avec le nom du fichier et les timecodes si vous souhaitez retrouver le passage dans la vidéo.
- **Une présentation adaptée :** choisissez une grille de 3 × 3 à 8 × 8, les proportions, la largeur de l’image et la couleur du fond.
- **Conçu pour Mac :** une application native en sept langues, avec une apparence claire, sombre ou suivant le système.

Prend en charge MP4, MOV, MPEG et les autres formats vidéo compatibles avec macOS.

### Voir l’application en action

Cette démonstration montre le passage d’une planche terminée au choix manuel des images. La chronologie permet de retrouver un moment, puis la galerie de choisir une autre image avant d’enregistrer.

![ShotMap passe de la planche Tears of Steel au choix manuel des images, avec chronologie et galerie](docs/assets/video-to-storyboard-demo.gif?v=20261101-release017)

## Télécharger et installer

Ouvrez la [dernière version](https://github.com/ixiehao/ShotMap/releases/latest) et choisissez **arm64** pour un Mac Apple Silicon (série M) ou **x86_64** pour un Mac Intel. Ouvrez le `.dmg` et glissez **ShotMap.app** dans **Applications**. Les deux versions comprennent les sept langues.

La page de version fournit une somme de contrôle SHA-256 pour vérifier le téléchargement. ShotMap n’est pas encore notarié par Apple. Si macOS demande de confirmer le développeur, faites un clic avec la touche Control enfoncée sur l’application dans Applications, choisissez **Ouvrir**, puis confirmez avec **Ouvrir**. Il n’est pas nécessaire de réduire les protections de sécurité du système.

### Choisir la langue

Changez de langue depuis la barre de menus macOS pour changer immédiatement, sans redémarrer ni vider la file de vidéos. Au premier lancement, ShotMap utilise la langue du système si elle est prise en charge, sinon l’anglais. Il mémorise ensuite votre choix.

## Vos vidéos restent privées

Vos vidéos restent sur votre Mac. ShotMap ne nécessite aucun compte et n’intègre ni suivi, ni envoi vers le cloud, ni moteur Electron, FFmpeg ou Python. La recherche facultative de mises à jour consulte uniquement les informations publiques des versions sur GitHub ; elle n’envoie ni vidéos ni données d’utilisation.

## Aide, retours et communauté

- **Vous découvrez ShotMap ?** Le [site officiel](https://ixiehao.github.io/ShotMap/fr/) présente l’application et ses captures réelles.
- **Besoin d’aide, un problème ou une suggestion ?** Consultez [l’aide](SUPPORT.md), puis utilisez un [formulaire de signalement](https://github.com/ixiehao/ShotMap/issues/new/choose) pour les problèmes reproductibles et les demandes de fonctions précises.
- **Une question ou une expérience à partager ?** Rejoignez [GitHub Discussions](https://github.com/ixiehao/ShotMap/discussions).
- **Envie de contribuer ?** Lisez [CONTRIBUTING.md](CONTRIBUTING.md). Signalez les failles de sécurité par le [canal privé](https://github.com/ixiehao/ShotMap/security/advisories/new).
- **Informations sur le projet :** [CHANGELOG.md](CHANGELOG.md) · [PRIVACY.md](PRIVACY.md) · [Développeur : ixiehao](https://github.com/ixiehao)

## Droits et licences

- Le code Swift, la documentation et l’icône de l’application sont des créations originales du projet, publiées sous [licence MIT](LICENSE).
- L’application utilise uniquement les frameworks des SDK Apple. Elle n’intègre aucun code d’application tiers, paquet logiciel, SDK d’analyse ou élément de MoviePrint.
- Les SVG [Tabler Icons Outline](https://github.com/tabler/tabler-icons) sont utilisés sans modification sous [licence MIT](ThirdPartyLicenses/TablerIcons-MIT.txt). La police Noto Sans CJK fournie est sous [SIL Open Font License 1.1](ThirdPartyLicenses/NotoSansCJK-OFL-1.1.txt). Voir [NOTICE.md](NOTICE.md).
- La vidéo de démonstration est *Tears of Steel* (2012) © Blender Foundation / Blender Institute, sous licence [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/).
- Traitez uniquement les vidéos que vous possédez ou êtes autorisé à analyser. Créer une planche ne donne aucun droit de publier ou de redistribuer la vidéo d’origine.

## Documentation de développement

[Index](docs/README.md) · [Développement et validation](docs/DEVELOPMENT.md) · [Maintenance du site](docs/WEBSITE.md).

Le code du site officiel se trouve dans `website/` ; `docs/` contient la documentation de maintenance.
