# Ruby base projects

## Ruby Base Clone and Rename
This repository provides a bash script, clone_and_rename.sh, which clones a specified Ruby base repository and then renames certain predefined elements.

The script performs the following operations:

1. Clones the ruby_base repository from Github into a directory with a user-provided name.
2. Deletes the .git directory inside the newly created directory and re-initializes Git.
3. Renames any files or directories within the new directory that start with "base_projects" to start with the user-provided name.
4. Replaces any occurrences of "BaseProject" in the files within the new directory with the CamelCase version of the user-provided name.
5. Replaces any occurrences of "base_projects" in the files within the new directory with the user-provided name.

### Usage
To use the script, you need to download it and make it executable. Here's a one-liner that accomplishes this, runs the script, and then deletes it:

```bash
wget https://raw.githubusercontent.com/zewelor/ruby_base/main/clone_and_rename.sh && chmod +x clone_and_rename && ./clone_and_rename new_project && rm clone_and_rename
```
In the command above, replace new_project with your desired name. This command will clone the repository and replace all occurrences of "base_projects" and "BaseProject" with your provided name and its CamelCase equivalent, respectively.

### Help
If you need help or want to view the usage instructions, you can download the script and run:

```bash
./clone_and_rename.sh -h
```
