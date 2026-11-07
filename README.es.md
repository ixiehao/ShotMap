<p><img src="website/assets/app-icon.png?v=20261101-release017" width="72" height="72" alt="ShotMap" /></p>

# ShotMap

[![Última versión](https://img.shields.io/github/v/release/ixiehao/ShotMap?display_name=tag&label=release&color=2563eb)](https://github.com/ixiehao/ShotMap/releases/latest)
[![Verificación](https://img.shields.io/github/actions/workflow/status/ixiehao/ShotMap/ci.yml?branch=main&label=verify)](https://github.com/ixiehao/ShotMap/actions/workflows/ci.yml)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111827?logo=apple)](https://github.com/ixiehao/ShotMap/releases/latest)
[![Licencia MIT](https://img.shields.io/badge/license-MIT-059669)](LICENSE)

[English](README.md) · [简体中文](README.zh-CN.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [Español](README.es.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

**La app está disponible en 7 idiomas:** English · 简体中文 · Français · Русский · Español · 日本語 · 한국어. Todos incluidos en una sola descarga.

![ShotMap en español creando un mosaico de Tears of Steel](website/assets/workspace-es.webp?v=20261101-release017)

*El ejemplo muestra la interfaz en inglés. La app también está disponible en español.*

## Las escenas de tu vídeo, en una sola imagen.

**ShotMap** es una app gratuita y de código abierto para Mac que reúne las escenas de un vídeo en un mosaico de imágenes. Revisa grabaciones familiares, viajes o material de edición sin abrir y recorrer cada archivo uno por uno.

Empieza con la selección automática y después sustituye o ajusta cualquier fotograma en la línea de tiempo. Añade varios vídeos para procesarlos por lotes y exporta imágenes PNG o JPG junto a los originales. Todo se procesa en tu Mac, sin cuenta ni subida de vídeos.

> **Empieza aquí:** [Descargar la última versión internacional](https://github.com/ixiehao/ShotMap/releases/latest) · DMG para Apple Silicon / Intel · macOS 13 o posterior · Apple Silicon e Intel

> **Vídeo de demostración:** *Tears of Steel* (2012) © Blender Foundation / Blender Institute, con licencia [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). Las capturas y la animación usan este vídeo.

## Para esos momentos que quieres volver a encontrar

- **Recuerdos personales y familiares:** localiza un cumpleaños, un viaje, una puesta de sol o los primeros pasos de un niño sin abrir cada archivo.
- **Creación y edición:** revisa un lote de vídeos antes de elegir el material que llevarás a tu programa de edición.
- **Organización de carpetas:** guarda un mosaico junto a cada vídeo original y añade marcas de tiempo y nombres de archivo si los necesitas.

## Del vídeo al mosaico en tres pasos

| 1. Añade vídeos | 2. Elige los momentos | 3. Guarda el mosaico |
| --- | --- | --- |
| Arrastra un vídeo o añade varios a la cola. | Usa Selección auto y ajusta los fotogramas a mano. | Exporta un PNG o JPG junto al vídeo original. |

## Elige las imágenes y su presentación

- **Una primera selección automática:** da prioridad a imágenes nítidas y variadas, intentando reducir los fotogramas negros, borrosos o casi repetidos.
- **Tú decides qué conservar:** usa el reproductor, la línea de tiempo y el avance fotograma a fotograma. La selección automática conserva tus elecciones y completa los espacios restantes.
- **Varios vídeos de una vez:** procesa un lote, ve cómo se completa la vista previa y pausa al terminar el vídeo actual.
- **Imágenes fáciles de ver y compartir:** exporta PNG o JPG, con nombres de archivo y códigos de tiempo opcionales para volver al vídeo original.
- **Un diseño a tu medida:** elige cuadrículas de 3 × 3 a 8 × 8, proporciones, anchura de imagen y color de fondo.
- **Hecho para Mac:** una app nativa con siete idiomas y apariencia clara, oscura o del sistema.

Compatible con MP4, MOV, MPEG y otros formatos de vídeo admitidos por macOS.

### Mira cómo funciona

Esta demostración muestra el paso de un mosaico terminado a la selección manual. Puedes localizar un momento en la línea de tiempo, elegir otra imagen en la galería y guardar el resultado.

![ShotMap pasa del mosaico de Tears of Steel a la selección manual de fotogramas, con línea de tiempo y galería](docs/assets/video-to-storyboard-demo.gif?v=20261101-release017)

## Descargar e instalar

Abre la [última versión](https://github.com/ixiehao/ShotMap/releases/latest) y elige **arm64** para un Mac con Apple Silicon (serie M) o **x86_64** para un Mac Intel. Abre el `.dmg` y arrastra **ShotMap.app** a **Aplicaciones**. Ambos instaladores incluyen los siete idiomas.

La página de la versión incluye una suma de comprobación SHA-256 para verificar la descarga. ShotMap aún no está notarizado por Apple. Si macOS pide confirmar el desarrollador, haz clic con la tecla Control pulsada en la app dentro de Aplicaciones, elige **Abrir** y vuelve a confirmar con **Abrir**. No necesitas reducir la seguridad del sistema.

### Elegir el idioma

Usa el menú de idiomas de la barra de menús de macOS para cambiar al instante, sin reiniciar ni vaciar la cola. Al abrirse por primera vez, ShotMap usa el idioma del sistema si está disponible; en caso contrario, usa inglés. Después recuerda tu elección.

## Tus vídeos se quedan en tu Mac

ShotMap no requiere cuenta, no hace seguimiento ni sube vídeos a la nube. Tampoco incluye Electron, FFmpeg ni un entorno de ejecución de Python. La comprobación opcional de actualizaciones solo consulta información pública de las versiones de GitHub; nunca envía vídeos ni datos de uso.

## Ayuda, comentarios y comunidad

- **¿Es tu primera vez con ShotMap?** Visita la [web oficial](https://ixiehao.github.io/ShotMap/es/) para ver una presentación breve y capturas reales.
- **¿Necesitas ayuda, has encontrado un fallo o tienes una idea?** Consulta [Soporte](SUPPORT.md) y usa un [formulario de incidencias](https://github.com/ixiehao/ShotMap/issues/new/choose) para errores reproducibles y propuestas concretas.
- **¿Quieres preguntar o compartir tu experiencia?** Participa en [GitHub Discussions](https://github.com/ixiehao/ShotMap/discussions).
- **¿Quieres colaborar?** Lee [CONTRIBUTING.md](CONTRIBUTING.md). Comunica los problemas de seguridad mediante el [canal privado](https://github.com/ixiehao/ShotMap/security/advisories/new).
- **Información del proyecto:** [CHANGELOG.md](CHANGELOG.md) · [PRIVACY.md](PRIVACY.md) · [Desarrollador: ixiehao](https://github.com/ixiehao)

## Derechos y licencias

- El código Swift, la documentación y el icono de la aplicación son creaciones originales del proyecto, publicadas bajo la [licencia MIT](LICENSE).
- La app solo usa frameworks de los SDK de Apple. No incluye código de aplicaciones de terceros, paquetes, SDK de análisis ni recursos de MoviePrint.
- Los SVG de [Tabler Icons Outline](https://github.com/tabler/tabler-icons) se usan sin modificar bajo la [licencia MIT](ThirdPartyLicenses/TablerIcons-MIT.txt). La fuente Noto Sans CJK incluida usa la [SIL Open Font License 1.1](ThirdPartyLicenses/NotoSansCJK-OFL-1.1.txt). Consulta [NOTICE.md](NOTICE.md).
- El vídeo de demostración es *Tears of Steel* (2012) © Blender Foundation / Blender Institute, con licencia [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/).
- Procesa solo vídeos que te pertenezcan o que tengas autorización para analizar. Crear un mosaico no concede derechos para publicar ni redistribuir el vídeo original.

## Documentación de desarrollo

[Índice](docs/README.md) · [Desarrollo y validación](docs/DEVELOPMENT.md) · [Mantenimiento de la web](docs/WEBSITE.md).

El código de la web oficial está en `website/`; `docs/` contiene la documentación de mantenimiento.
