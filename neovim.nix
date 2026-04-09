{ pkgs, lib, ... }:

{
  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    globals.mapleader = " ";

    opts = {
      number = true;
      relativenumber = true;
      shiftwidth = 2;
      tabstop = 2;
      expandtab = true;
      clipboard = "unnamedplus";
      mouse = "a";
      signcolumn = "yes";
      termguicolors = true;
      updatetime = 250;
      undofile = true;
      ignorecase = true;
      smartcase = true;
    };

    # ── Colorscheme ──────────────────────────────────────────────
    colorschemes.catppuccin = {
      enable = true;
      settings.flavour = "mocha";
    };

    # ── LSP ──────────────────────────────────────────────────────
    plugins.lsp = {
      enable = true;
      servers = {
        gopls.enable = true;
        pyright.enable = true;
        clangd.enable = true;
        # rust-analyzer is managed by rustaceanvim below
      };
      keymaps = {
        lspBuf = {
          "gd" = "definition";
          "gD" = "declaration";
          "gr" = "references";
          "gi" = "implementation";
          "K" = "hover";
          "<leader>ca" = "code_action";
          "<leader>rn" = "rename";
        };
        diagnostic = {
          "[d" = "goto_prev";
          "]d" = "goto_next";
          "<leader>dl" = "open_float";
        };
      };
    };

    # ── Rust (rustaceanvim) ──────────────────────────────────────
    plugins.rustaceanvim.enable = true;

    # ── Treesitter ───────────────────────────────────────────────
    plugins.treesitter = {
      enable = true;
      settings = {
        ensure_installed = [
          "go" "python" "rust" "c" "cpp"
          "lua" "nix" "bash"
          "json" "yaml" "toml"
          "markdown" "markdown_inline"
          "dockerfile"
        ];
        highlight.enable = true;
        indent.enable = true;
      };
    };

    # ── Completion ───────────────────────────────────────────────
    plugins.blink-cmp = {
      enable = true;
      settings = {
        keymap.preset = "super-tab";
        sources.default = [ "lsp" "path" "snippets" "buffer" ];
      };
    };

    # ── Telescope ────────────────────────────────────────────────
    plugins.telescope = {
      enable = true;
      keymaps = {
        "<leader>ff" = { action = "find_files"; options.desc = "Find files"; };
        "<leader>fg" = { action = "live_grep";  options.desc = "Live grep"; };
        "<leader>fb" = { action = "buffers";    options.desc = "Buffers"; };
        "<leader>fh" = { action = "help_tags";  options.desc = "Help tags"; };
      };
    };

    # ── Neo-tree ─────────────────────────────────────────────────
    plugins.neo-tree.enable = true;

    # ── UI ───────────────────────────────────────────────────────
    plugins.web-devicons.enable = true;
    plugins.lualine.enable = true;
    plugins.which-key.enable = true;
    plugins.gitsigns.enable = true;
    plugins.render-markdown.enable = true;

    # ── Formatting ───────────────────────────────────────────────
    plugins.conform-nvim = {
      enable = true;
      settings = {
        formatters_by_ft = {
          go = [ "gofmt" ];
          python = [ "ruff_format" ];
          rust = [ "rustfmt" ];
          c = [ "clang-format" ];
          cpp = [ "clang-format" ];
          nix = [ "nixfmt" ];
        };
        format_on_save = {
          timeout_ms = 500;
          lsp_format = "fallback";
        };
      };
    };

    # ── Toggleterm ───────────────────────────────────────────────
    plugins.toggleterm = {
      enable = true;
      settings = {
        open_mapping = "[[<C-\\>]]";
        direction = "horizontal";
        size = 20;
      };
    };

    # ── Snacks (required by claudecode.nvim) ────────────────────
    plugins.snacks.enable = true;

    # ── Claude Code (claudecode.nvim) ────────────────────────────
    # Plugin from coder/claudecode.nvim — pinned to v0.3.0
    # To update the hash: nix-prefetch-github coder claudecode.nvim --rev v0.3.0
    extraPlugins = [
      (pkgs.vimUtils.buildVimPlugin {
        pname = "claudecode-nvim";
        version = "0.3.0";
        src = pkgs.fetchFromGitHub {
          owner = "coder";
          repo = "claudecode.nvim";
          rev = "v0.3.0";
          hash = "sha256-sOBY2y/buInf+SxLwz6uYlUouDULwebY/nmDlbFbGa8=";  # build once — Nix will print the correct hash
        };
      })
    ];

    extraConfigLua = ''
      -- claudecode.nvim setup
      require("claudecode").setup({})
      vim.keymap.set("n", "<leader>ac", "<cmd>ClaudeCode<cr>", { desc = "Toggle Claude Code" })
      vim.keymap.set("n", "<leader>af", "<cmd>ClaudeCodeFocus<cr>", { desc = "Focus Claude Code" })
      vim.keymap.set("v", "<leader>as", "<cmd>ClaudeCodeSend<cr>", { desc = "Send selection to Claude" })

      -- Neo-tree toggle
      vim.keymap.set("n", "<leader>e", "<cmd>Neotree toggle<cr>", { desc = "Toggle file explorer" })

      -- Claude terminal via toggleterm
      local Terminal = require("toggleterm.terminal").Terminal
      local claude_term = Terminal:new({
        cmd = "claude",
        direction = "horizontal",
        hidden = true,
      })
      vim.keymap.set("n", "<leader>at", function() claude_term:toggle() end, { desc = "Toggle Claude terminal" })
    '';
  };
}
