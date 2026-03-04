#!/usr/bin/env python3
"""
sync_pbxproj.py - Auto-register new .swift files in the Xcode project.
Scans Views/, ViewModels/, Services/, App/ for .swift files not yet in pbxproj
and adds them to PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase.
Uses line-by-line insertion for reliability.
"""
import os, hashlib

PROJECT_FILE = "HarpoOutreach.xcodeproj/project.pbxproj"

# Folders to scan and their PBXGroup comment markers
FOLDER_GROUPS = {
    "Views": "Views",
    "ViewModels": "ViewModels",
    "Services": "Services",
    "App": "App",
}

def generate_id(seed: str) -> str:
    """Generate a deterministic 24-char hex ID from a seed string."""
    h = hashlib.md5(seed.encode()).hexdigest().upper()
    return h[:24]

def get_registered_files(lines: list) -> set:
    """Extract all .swift filenames already referenced in PBXFileReference lines."""
    files = set()
    for line in lines:
        if 'PBXFileReference' in line and '.swift' in line:
            # Extract filename from: path = SomeFile.swift; or path = "Some+File.swift";
            for part in line.split(';'):
                part = part.strip()
                if part.startswith('path'):
                    val = part.split('=', 1)[1].strip().strip('"').strip()
                    if val.endswith('.swift'):
                        files.add(val)
    return files

def find_swift_files(folder: str) -> list:
    if not os.path.isdir(folder):
        return []
    return sorted([f for f in os.listdir(folder) if f.endswith('.swift')])

def add_files_to_pbxproj(lines: list, files_to_add: list) -> list:
    """
    files_to_add: list of (folder, filename) tuples
    Modifies lines in-place to add entries in all 4 required sections.
    """
    new_lines = []
    
    # Pre-compute IDs
    entries = []
    for folder, filename in files_to_add:
        file_ref_id = generate_id(f"fileref_{folder}_{filename}")
        build_file_id = generate_id(f"buildfile_{folder}_{filename}")
        needs_quote = '+' in filename or '-' in filename
        path_value = f'"{filename}"' if needs_quote else filename
        entries.append({
            'folder': folder,
            'filename': filename,
            'file_ref_id': file_ref_id,
            'build_file_id': build_file_id,
            'path_value': path_value,
        })
    
    in_build_file_section = False
    in_file_ref_section = False
    in_sources_phase = False
    found_sources_files = False
    
    # Track which groups we need to add children to
    # We'll look for the group by its path comment and add before the closing );
    current_group_folder = None
    looking_for_children_end = False
    
    for i, line in enumerate(lines):
        stripped = line.strip()
        
        # 1. PBXBuildFile section end
        if stripped == '/* End PBXBuildFile section */':
            for e in entries:
                bf_line = f'\t\t{e["build_file_id"]} /* {e["filename"]} in Sources */ = {{isa = PBXBuildFile; fileRef = {e["file_ref_id"]} /* {e["filename"]} */; }};\n'
                new_lines.append(bf_line)
            new_lines.append(line)
            continue
        
        # 2. PBXFileReference section end
        if stripped == '/* End PBXFileReference section */':
            for e in entries:
                fr_line = f'\t\t{e["file_ref_id"]} /* {e["filename"]} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {e["path_value"]}; sourceTree = "<group>"; }};\n'
                new_lines.append(fr_line)
            new_lines.append(line)
            continue
        
        # 3. PBXGroup - detect folder groups and add children
        # Look for lines like: /* Views */ = {
        # Then find the children list and add before closing );
        for folder_name in FOLDER_GROUPS.values():
            if f'/* {folder_name} */' in stripped and '= {' in stripped and 'PBXGroup' not in stripped:
                current_group_folder = folder_name
                break
        
        if current_group_folder and 'children = (' in stripped:
            looking_for_children_end = True
        
        if looking_for_children_end and stripped == ');':
            # Add new children for this group
            folder_entries = [e for e in entries if FOLDER_GROUPS.get(e['folder']) == current_group_folder]
            for e in folder_entries:
                child_line = f'\t\t\t\t{e["file_ref_id"]} /* {e["filename"]} */,\n'
                new_lines.append(child_line)
            looking_for_children_end = False
            current_group_folder = None
        
        # 4. PBXSourcesBuildPhase - add to files list
        if '/* Sources */' in stripped and 'PBXSourcesBuildPhase' not in stripped and '= {' in stripped:
            in_sources_phase = True
        
        if in_sources_phase and 'files = (' in stripped:
            found_sources_files = True
        
        if in_sources_phase and found_sources_files and stripped == ');':
            for e in entries:
                src_line = f'\t\t\t\t{e["build_file_id"]} /* {e["filename"]} in Sources */,\n'
                new_lines.append(src_line)
            found_sources_files = False
            in_sources_phase = False
        
        new_lines.append(line)
    
    return new_lines

def main():
    if not os.path.exists(PROJECT_FILE):
        print(f"[sync_pbxproj] Project file not found: {PROJECT_FILE}")
        return

    with open(PROJECT_FILE, 'r') as f:
        lines = f.readlines()

    registered = get_registered_files(lines)
    files_to_add = []

    for folder in FOLDER_GROUPS:
        swift_files = find_swift_files(folder)
        for filename in swift_files:
            if filename not in registered:
                print(f"[sync_pbxproj] Adding {folder}/{filename}")
                files_to_add.append((folder, filename))

    if files_to_add:
        new_lines = add_files_to_pbxproj(lines, files_to_add)
        with open(PROJECT_FILE, 'w') as f:
            f.writelines(new_lines)
        print(f"[sync_pbxproj] Added {len(files_to_add)} file(s) to project")
    else:
        print("[sync_pbxproj] All files already registered")

if __name__ == '__main__':
    main()
