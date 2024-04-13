if (vim.env.JDTLS_ENABLED == "true") then
    return {
        "mfussenegger/nvim-jdtls",
        config = function()
            local jdtlsPath = vim.env.JDTLS_DIR
            local config = {
                cmd = { string.format("%s/bin/jdtls", jdtlsPath) },
                root_dir = vim.fs.dirname(vim.fs.find({ 'gradlew', 'mvnw' }, { upward = true })[1]),
            }

            require('jdtls').start_or_attach(config)
        end
    }
else
    return {};
end
