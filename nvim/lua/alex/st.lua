function SteampipeQuery()
    local filepath = vim.fn.expand('%:p')
    local filename = vim.fn.expand('%:t')
    local filedir = vim.fn.expand('%:p:h')
    vim.fn.system('mkdir -p ' .. filedir .. '/output')

    local time = os.time()
    local resultfilename = filedir .. '/output/' .. filename .. '-' .. time .. '.result'
    local errorsfilename =  filedir .. '/output/' .. filename .. '-' .. time .. '.errors'


    local spcommand = 'steampipe query ' .. vim.fn.shellescape(filename) .. ' >' .. resultfilename .. ' 2>' .. errorsfilename
    vim.fn.systemlist(spcommand)

    local errorsexistcommand = 'test -s ' .. errorsfilename
    if vim.fn.system(errorsexistcommand) == 0 then
        vim.fn.system('rm ' .. errorsfilename)
    else
        vim.api.nvim_command('new ' .. errorsfilename)
    end

    vim.api.nvim_command('new ' .. resultfilename)
end

vim.cmd("command! -nargs=0 St lua SteampipeQuery()")
