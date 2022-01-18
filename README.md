# dot
The start of your dotfiles!

## Usage

1. read [`./dotfiles_init.sh`](./dotfiles_init.sh) carefully
2. download it with
    ```sh
    target_file="/tmp/dotfiles_init.sh"
    url=https://raw.githubusercontent.com/SKalt/dot/main/dotfiles_init.sh

    curl -Lo "$target_file"
    # `-L` means follow redirects
    # `-o "$target_file"` where to put the download

    # check you're getting what you expected:
    shasum -a 256 "$target_file"
    # should print 70af2e23b654eec050d831e6385c3fcf92cdf2b2102813e13cdbc4f8641f7939  /tmp/dotfiles_init.sh
    ```
3. run the setup script with
    ```sh
    chmod +x /tmp/dotfiles_init.sh
    /tmp/dotfiles_init.sh
    ```
4. Manage your home directory as a bare git directory, using `dotfiles` as an alias for `git`

5. When you want to set up a new machine with your existing dotfiles:
    ```sh
    # make sure you've moved all pre-existing dotfiles to other backup locations.
    # For example, you might`mv ~/.bashrc ~/.bashrc.bak`
    dotfiles_git_dir="${dotfiles_git_dir:-$HOME/.dotfiles.git}"
    git clone --bare "$your_dotfiles_repo" $dotfiles_git_dir
    alias dotfiles="git --git-dir=$dotfiles_git_dir --work-tree=$HOME"
    dotfiles config core.excludesFile $HOME/.dotfiles/dotfiles_exclude
    dotfiles checkout
    ```
