{
  description = "Reusable values from DictXiong's dotfiles";

  outputs =
    { self }:
    let
      files = {
        authorizedKeys = ./.ssh/authorized_keys2;
        authorizedCertificates = ./.eid/authorized_certificates;
        git = ./.gitconfig2;
        tmux = ./.tmux.conf2;
        vim = ./.vimrc2;
        zsh = ./.zshrc2;
      };
      authorizedKeys = builtins.filter (
        line: builtins.isString line && builtins.match "[[:blank:]]*(#.*)?" line == null
      ) (builtins.split "\r?\n" (builtins.readFile files.authorizedKeys));
    in
    {
      lib = {
        inherit files;
        ssh = {
          inherit authorizedKeys;
          selectAuthorizedKeys =
            names:
            map (
              name:
              let
                matches = builtins.filter (
                  key:
                  builtins.match "[[:blank:]]*[^[:blank:]]+[[:blank:]]+[A-Za-z0-9+/=]+[[:blank:]]+(.*[^[:blank:]])[[:blank:]]*" key
                  == [ name ]
                ) authorizedKeys;
              in
              if builtins.length matches == 1 then
                builtins.head matches
              else
                throw "dotfiles: expected exactly one SSH authorized key with comment '${name}'"
            ) names;
        };
      };
    };
}
