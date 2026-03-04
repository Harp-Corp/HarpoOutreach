#!/usr/bin/env python3
"""
sync_pbxproj.py - Auto-register new .swift files in the Xcode project.
Scans Views/, ViewModels/, Services/, App/ for .swift files not yet in pbxproj
and adds them to PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase.
"""
import os, re, uuid, hashlib

PROJECT_FILE = "HarpoOutreach.xcodeproj/project.pbxproj"

# Folders to scan and their PBXGroup IDs (from existing pbxproj)
FOLDER_GROUPS = {
    "Views": "EF44A7862F4108470054C161",
    "ViewModels": "EF67ADB92F421FF00066E6E9",
    "Services": "EF44A7832F4108470054C161",
    "App": "EF44A77F2F4108470054C161",
}

SOURCES_PHASE = "EF44A7202F40DCEF0054C161"

def generate_id(seed: str) -> str:
    """Generate a deterministic 24-char hex ID from a seed string."""
    h = hashlib.md5(seed.encode()).hexdigest().upper()
    return h[:24]

def get_registered_files(content: str) -> set:
    """Extract all filenames already in PBXFileReference."""
    pattern = r'/\*\s+([\w+\-\.]+\.swift)\s+\*/'
    return set(re.findall(pattern, content))

def find_swift_files(folder: str) -> list:
    """Find all .swift files in a folder."""
    if not os.path.isdir(folder):
        return []
    return [f for f in os.listdir(folder) if f.endswith('.swift')]

def add_file_to_pbxproj(content: str, filename: str, folder: str) -> str:
    """Add a single .swift file to all required sections."""
    group_id = FOLDER_GROUPS.get(folder)
    if not group_id:
        return content

    # Generate deterministic IDs
    file_ref_id = generate_id(f"fileref_{folder}_{filename}")
    build_file_id = generate_id(f"buildfile_{folder}_{filename}")

    # Determine if filename needs quoting (contains +)
    needs_quote = '+' in filename or '-' in filename
    path_value = f'"{filename}"' if needs_quote else filename

    # 1. Add PBXBuildFile entry
    build_file_line = f'\t\t{build_file_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* {filename} */; }};'
    content = content.replace(
        '/* End PBXBuildFile section */',
        f'{build_file_line}\n/* End PBXBuildFile section */'
    )

    # 2. Add PBXFileReference entry
    file_ref_line = f'\t\t{file_ref_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {path_value}; sourceTree = "<group>"; }};'
    content = content.replace(
        '/* End PBXFileReference section */',
        f'{file_ref_line}\n/* End PBXFileReference section */'
    )

    # 3. Add to PBXGroup children
    # Find the group and add before its closing );
    group_pattern = f'{group_id} /\\* {folder} \\*/ = {{{{[^}}]*?children = \\(([^)]*?)\\)'
    match = re.search(group_pattern, content, re.DOTALL)
    if match:
        children_content = match.group(1)
        new_child = f'\n\t\t\t\t{file_ref_id} /* {filename} */,'
        new_children = children_content + new_child
        content = content.replace(children_content, new_children, 1)

    # 4. Add to PBXSourcesBuildPhase
    sources_pattern = f'{SOURCES_PHASE} /\\* Sources \\*/ = {{{{[^}}]*?files = \\(([^)]*?)\\)'
    match = re.search(sources_pattern, content, re.DOTALL)
    if match:
        files_content = match.group(1)
        new_file = f'\n\t\t\t\t{build_file_id} /* {filename} in Sources */,'
        new_files = files_content + new_file
        content = content.replace(files_content, new_files, 1)

    return content

def main():
    if not os.path.exists(PROJECT_FILE):
        print(f"[sync_pbxproj] Project file not found: {PROJECT_FILE}")
        return

    with open(PROJECT_FILE, 'r') as f:
        content = f.read()

    registered = get_registered_files(content)
    added = 0

    for folder in FOLDER_GROUPS:
        swift_files = find_swift_files(folder)
        for filename in swift_files:
            if filename not in registered:
                print(f"[sync_pbxproj] Adding {folder}/{filename}")
                content = add_file_to_pbxproj(content, filename, folder)
                added += 1

    if added > 0:
        with open(PROJECT_FILE, 'w') as f:
            f.write(content)
        print(f"[sync_pbxproj] Added {added} file(s) to project")
    else:
        print("[sync_pbxproj] All files already registered")

if __name__ == '__main__':
    main()
