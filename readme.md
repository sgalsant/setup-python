# Guía paso a paso: VS Code, Python, entornos virtuales y uv en Windows 11

## 1. Objetivo

Esta guía prepara un entorno local, reproducible y fácil de mantener para trabajar con Python y notebooks de análisis de datos.

Está pensada para equipos Windows 11 en los que el alumnado:

- no tiene permisos de administrador;
- puede no tener Python instalado;
- instala VS Code en su propio perfil;
- trabaja con archivos `.ipynb` dentro de VS Code;
- necesita repetir la instalación en su ordenador de casa.

No es necesario instalar Python globalmente ni instalar JupyterLab como aplicación independiente.

## 2. Componentes

| Componente | Función |
|---|---|
| VS Code User Setup | Editor, terminal, depurador y editor de notebooks |
| Extensión Python | IntelliSense, ejecución, selección de intérprete y depuración |
| Extensión Jupyter | Ejecución de archivos `.ipynb` |
| `uv` | Gestión de Python, dependencias y entornos |
| Python 3.13 | Intérprete del curso |
| `.venv` | Entorno virtual aislado de cada proyecto |

La organización será:

```text
VS Code
  ├── Python
  ├── Jupyter
  └── interpreter: project\.venv\Scripts\python.exe

uv ── manages ── Python 3.13
uv ── creates and synchronizes ── .venv
uv ── installs ── project packages
```

## 3. Requisitos previos

1. Utiliza una cuenta normal de Windows.
2. Trabaja en una carpeta de tu perfil, por ejemplo:

   ```text
   C:\Users\TU_USUARIO\projects
   ```

3. No guardes el proyecto en `Program Files`, una carpeta del sistema o una ubicación de red.
4. Necesitarás conexión a Internet durante la primera instalación.
5. Después de instalar VS Code o `uv`, cierra y vuelve a abrir el terminal.

## 4A. Proceso con el script PowerShell

El archivo `setup_python_environment.ps1` instala por defecto las herramientas del equipo: VS Code por usuario, extensiones Python y Jupyter, `uv` y Python 3.13. No crea ningún proyecto ni entorno virtual en este modo.

Para crear además un proyecto de análisis de datos con sus dependencias y `.venv`, añade el parámetro `-PyData` (PowerShell no distingue mayúsculas y minúsculas, por lo que `-pydata` también funciona).

Elige este método para la instalación inicial de un alumno o para preparar equipos con la misma configuración. Si usas este método, omite el apartado **4B** y continúa directamente en el apartado **5**.

### Paso 1. Guardar el script

1. Descarga `setup_python_environment.ps1`.
2. Guárdalo en una carpeta de tu perfil, por ejemplo:

   ```text
   C:\Users\TU_USUARIO\Downloads\python-environment-setup
   ```

3. Abre PowerShell sin permisos de administrador.
4. Sitúate en esa carpeta:

   ```powershell
   Set-Location "$HOME\Downloads\python-environment-setup"
   Get-ChildItem .\setup_python_environment.ps1
   ```

El segundo comando debe mostrar el archivo del script.

### Paso 2. Ver el plan de instalación

Antes de cambiar nada, ejecuta:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup_python_environment.ps1 -WhatIf
```

`-WhatIf` solo muestra las acciones previstas. No descarga ni instala ningún componente.

### Paso 3. Ejecutar la instalación automatizada

```powershell
powershell -ExecutionPolicy Bypass -File .\setup_python_environment.ps1 -Verbose
```

`-ExecutionPolicy Bypass` se aplica únicamente a esta ejecución; no modifica permanentemente la política de PowerShell. `-Verbose` muestra las etapas y comandos ejecutados.

En modo base, el script realiza, en este orden:

1. Comprueba si VS Code está instalado y, si es necesario, instala **VS Code User Setup**.
2. Instala o actualiza las extensiones oficiales `ms-python.python` y `ms-toolsai.jupyter`.
3. Instala `uv` en el perfil del usuario.
4. Instala Python 3.13 oficial para el usuario actual.
5. Comprueba que las herramientas instaladas están disponibles.

Con `-PyData` también crea un proyecto con `numpy`, `pandas`, `matplotlib`, `seaborn`, `ipykernel`, `ruff` y `pytest`, y sincroniza su `.venv`.

Si se usa `-PyData` sin `-ProjectPath`, el proyecto se crea junto al script en la primera carpeta disponible: `pydata`, `pydata2`, `pydata3`, etc. Si se indica `-ProjectPath` y la carpeta no existe, el script la crea.

Si ya existe un proyecto con `uv.lock`, se ejecuta `uv sync --locked` para conservar exactamente las versiones fijadas.

### Paso 4. Interpretar el resultado

La instalación ha terminado bien cuando aparece:

```text
Check completed successfully.
```

Después continúa en el apartado **5. Configuración común en VS Code**.

Si se muestra un error de descarga, revisa la conexión y las restricciones de red del centro. Si el error aparece tras instalar VS Code o `uv`, cierra PowerShell, abre una ventana nueva y vuelve a ejecutar el script.

### Paso 5. Comprobar una instalación existente

En cualquier momento puedes revisar el entorno sin modificarlo:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup_python_environment.ps1 -Check
```

La comprobación sin parámetros valida VS Code, sus extensiones, `uv` y Python. Para comprobar un proyecto de datos, indica su ruta: `-Check -ProjectPath "ruta"`.

### Paso 6. Reparar o reinstalar el entorno

Si el entorno se ha dañado:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup_python_environment.ps1 -Reinstall -Verbose
```

Esta opción actualiza o reinstala `uv`, reinstala Python 3.13 y vuelve a instalar los paquetes de `.venv`. Respeta `uv.lock`; por ello no cambia arbitrariamente las versiones del proyecto.

### Paso 7. Opciones adicionales

| Opción | Acción |
|---|---|
| `-Verbose` | Explica cada fase y comando. |
| `-Check` | Solo comprueba; no modifica el equipo. |
| `-Reinstall` | Reinstala `uv` y reconstruye `.venv` cuando se usa con `-PyData`. |
| `-PyData` | Crea un proyecto de análisis de datos, sus dependencias y `.venv`. Acepta cualquier combinación de mayúsculas/minúsculas. |
| `-IncludeExcelAndParquet` | Añade `openpyxl` y `pyarrow` cuando crea un proyecto nuevo. |
| `-ProjectPath "ruta"` | Cambia la ubicación del proyecto. |
| `-WhatIf` | Muestra el plan sin ejecutarlo. |

Con `-PyData`, si no se especifica `-ProjectPath`, el proyecto se crea en una subcarpeta disponible junto a `setup_python_environment.ps1`. Por ejemplo, si el script está en:

```text
C:\Users\TU_USUARIO\Downloads\python-environment-setup
```

se creará `pydata` (o `pydata2`, si `pydata` ya existe) y dentro de ella se crearán `.venv`, `pyproject.toml`, `uv.lock`, `notebooks` y `data`.

Ejemplo con una ruta alternativa:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup_python_environment.ps1 -PyData -ProjectPath "$HOME\projects\data-analysis" -IncludeExcelAndParquet -Verbose
```

## 4B. Proceso sin el script: instalación manual

### Paso 1. Instalar VS Code por usuario

1. Descarga VS Code desde su [página oficial](https://code.visualstudio.com/download).
2. Elige **User Installer** para Windows.
3. Ejecuta el instalador desde tu cuenta normal.
4. Mantén las opciones predeterminadas.
5. Si aparece la opción, activa **Add to PATH**.

La opción **User Setup** no requiere permisos de administrador y se instala en el perfil del usuario.

Abre un PowerShell nuevo y comprueba:

```powershell
code --version
```

Si `code` no se reconoce, VS Code seguirá funcionando desde el menú Inicio. Puedes reiniciar sesión en Windows para actualizar el `PATH`.

### Paso 2. Instalar las extensiones

En VS Code, pulsa `Ctrl+Shift+X` y busca estas extensiones oficiales:

1. **Python**, publicada por Microsoft.
2. **Jupyter**, publicada por Microsoft.

Con ellas se puede editar, ejecutar y depurar código Python, además de abrir notebooks dentro de VS Code.

### Paso 3. Instalar uv sin permisos de administrador

Abre **PowerShell**, sin usar «Ejecutar como administrador», y ejecuta:

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

Cierra PowerShell, abre una ventana nueva y comprueba:

```powershell
uv --version
Get-Command uv
```

Si `uv` no se reconoce, cierra también el terminal integrado de VS Code y vuelve a abrirlo. Si continúa el problema, reinicia Windows.

El instalador independiente de `uv` no necesita que Python esté instalado previamente.

### Paso 4. Instalar Python 3.13 con uv

Ejecuta:

```powershell
uv python install 3.13
uv python list
```

Para este curso se utilizará Python 3.13 gestionado por `uv`. No es imprescindible que el comando global `python` funcione: las órdenes del proyecto se ejecutarán con `uv run` o con el intérprete de `.venv`.

### Paso 5. Crear la carpeta de trabajo

```powershell
New-Item -ItemType Directory -Path "$HOME\projects" -Force
Set-Location "$HOME\projects"
Get-Location
```

La ruta resultante será parecida a:

```text
C:\Users\TU_USUARIO\projects
```

### Paso 6. Crear el proyecto

```powershell
New-Item -ItemType Directory -Path ".\data-analysis-python" -Force
Set-Location ".\data-analysis-python"
uv init --python 3.13
New-Item -ItemType Directory -Path ".\notebooks" -Force
New-Item -ItemType Directory -Path ".\data" -Force
```

La raíz del proyecto debe abrirse completa en VS Code, no solo la carpeta `notebooks`.

La estructura básica será:

```text
data-analysis-python/
├── .python-version     # Project Python version
├── .venv/              # Local virtual environment
├── pyproject.toml      # Dependencies and project configuration
├── uv.lock             # Exact resolved versions
├── notebooks/          # .ipynb files
├── data/               # Data files
└── src/                # Reusable Python code, if needed
```

### Paso 7. Añadir las bibliotecas

Para el módulo de Análisis de datos con Python:

```powershell
uv add numpy pandas matplotlib seaborn
uv add --dev ipykernel ruff pytest
```

Si se van a utilizar Excel y Parquet:

```powershell
uv add openpyxl pyarrow
```

`uv add` registra cada dependencia en `pyproject.toml`, actualiza `uv.lock` y sincroniza el entorno.

No se recomienda instalar paquetes manualmente con `pip install`. Si una biblioteca forma parte del proyecto debe quedar declarada en los archivos del proyecto.

### Paso 8. Crear y comprobar el entorno

```powershell
uv sync
uv run python --version
uv run python -c "import sys; print(sys.executable)"
uv run python -c "import numpy, pandas, matplotlib, seaborn; print('Environment ready')"
```

El ejecutable mostrado debe estar dentro de una ruta parecida a:

```text
...\data-analysis-python\.venv\Scripts\python.exe
```

`uv sync` crea `.venv` si no existe y la deja conforme a `pyproject.toml` y `uv.lock`.

## 5. Configuración común en VS Code

Desde la raíz del proyecto:

```powershell
code .
```

Si el comando `code` no está disponible, abre VS Code desde el menú Inicio y utiliza **File > Open Folder**.

### 5.1. Seleccionar el intérprete de Python

1. Pulsa `Ctrl+Shift+P`.
2. Ejecuta **Python: Select Interpreter**.
3. Selecciona el intérprete que termine en:

   ```text
   .venv\Scripts\python.exe
   ```

4. Si no aparece, selecciona **Enter interpreter path...** y localiza ese archivo.

Si VS Code no lo detecta:

```powershell
Test-Path ".\.venv\Scripts\python.exe"
uv sync
```

Después ejecuta **Developer: Reload Window** y vuelve a seleccionar el intérprete.

### 5.2. Crear y ejecutar un notebook

1. Abre la carpeta `notebooks`.
2. Crea `01_environment_check.ipynb`.
3. Pulsa **Select Kernel** en la parte superior derecha.
4. Selecciona el entorno de `data-analysis-python\.venv`.

En una celda de código escribe:

```python
import sys

import numpy as np
import pandas as pd

print(sys.executable)
print(sys.version)
print(np.__version__)
print(pd.__version__)
```

Ejecuta la celda con el botón de reproducción o con `Shift+Enter`. `sys.executable` debe apuntar a `.venv\Scripts\python.exe`.

## 6. Uso diario del entorno

La activación es opcional si se utiliza `uv run`. En PowerShell:

```powershell
.venv\Scripts\Activate.ps1
```

Para salir:

```powershell
deactivate
```

Si PowerShell bloquea `Activate.ps1`, no cambies la política de todo el equipo. Puedes trabajar así:

```powershell
uv run python my_script.py
uv run jupyter --version
```

Como alternativa, permite scripts solo durante la ventana actual:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.venv\Scripts\Activate.ps1
```

### 6.1. Flujo diario recomendado

```powershell
Set-Location "$HOME\projects\data-analysis-python"
uv sync --locked
code .
```

Para ejecutar un script:

```powershell
uv run python src\my_script.py
```

Para añadir una biblioteca:

```powershell
uv add package-name
uv sync
```

Para actualizar una dependencia concreta:

```powershell
uv lock --upgrade-package package-name
uv sync
```

## 7. Reproducir el entorno en otro ordenador

No copies `.venv` entre ordenadores. Contiene rutas propias de cada equipo.

Conserva:

```text
pyproject.toml
uv.lock
.python-version
notebooks/
src/
data/
```

En el nuevo ordenador:

```powershell
Set-Location "C:\path\data-analysis-python"
uv sync --locked
code .
```

`uv` instalará lo necesario y reconstruirá `.venv`.

## 8. Archivos que no se deben versionar

En `.gitignore` incluye:

```gitignore
.venv/
__pycache__/
*.pyc
.ipynb_checkpoints/
.env
data/raw/
```

Los notebooks sí deben conservarse cuando contienen explicaciones, código y resultados.

## 9. Verificación final

La instalación es correcta cuando funcionan:

```powershell
uv --version
uv python list
uv run python --version
uv run python -c "import sys; print(sys.executable)"
uv run python -c "import numpy, pandas, matplotlib, seaborn; print('OK')"
```

También debe cumplirse que:

- VS Code abre la carpeta completa del proyecto.
- El intérprete seleccionado es `.venv\Scripts\python.exe`.
- El kernel del notebook corresponde al mismo entorno.
- Una celda con `import pandas as pd` se ejecuta sin error.
- `uv sync` termina correctamente.

## 10. Solución de problemas

### `uv` no se reconoce

Cierra y abre el terminal. Si persiste, reinicia Windows. Comprueba `Get-Command uv`.

### `python` no se reconoce

No es necesariamente un error. Usa:

```powershell
uv run python --version
```

### VS Code utiliza otro Python

Ejecuta **Python: Select Interpreter** y selecciona `.venv\Scripts\python.exe`. En el notebook selecciona además el kernel correcto.

### Falta `ipykernel`

```powershell
uv add --dev ipykernel
uv sync
```

Después reinicia el kernel.

### No se pueden descargar paquetes

Comprueba la conexión y si la red del centro bloquea PyPI o GitHub. En una red con proxy corporativo puede ser necesario aplicar la configuración del centro.

### El entorno está dañado

```powershell
uv sync --locked --reinstall
```

Si continúa el problema, cierra VS Code, elimina únicamente la carpeta `.venv` del proyecto y ejecuta de nuevo `uv sync`. No elimines `pyproject.toml` ni `uv.lock`.

## 11. Resumen de comandos manuales

```powershell
# Install uv
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"

# Install Python
uv python install 3.13

# Create the project
New-Item -ItemType Directory -Path ".\data-analysis-python" -Force
Set-Location ".\data-analysis-python"
uv init --python 3.13

# Install dependencies
uv add numpy pandas matplotlib seaborn
uv add --dev ipykernel ruff pytest

# Create or update .venv
uv sync

# Check and open
uv run python --version
code .
```

## Fuentes oficiales

- [Instalación de VS Code en Windows](https://code.visualstudio.com/docs/setup/windows)
- [Python en VS Code](https://code.visualstudio.com/docs/python/python-quick-start)
- [Notebooks en VS Code](https://code.visualstudio.com/docs/python/jupyter-support-py)
- [Instalación de uv](https://docs.astral.sh/uv/getting-started/installation/)
- [Python gestionado por uv](https://docs.astral.sh/uv/guides/install-python/)
- [Proyectos con uv](https://docs.astral.sh/uv/guides/projects/)

_Guía adaptada al curso de especialización de Desarrollo de aplicaciones en lenguaje Python, especialmente al módulo de Análisis de datos con Python._
