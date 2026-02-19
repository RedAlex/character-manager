let config = {};
let currentSearchType = 'wipe';
let selectedPlayer = null;
let selectedCharacter = null;
let characterList = [];
let availableVehicles = [];
let selectedVehiclePlates = [];
let vehicleAction = 'delete';
let transferTarget = null;

// Utility functions
function post(url, data) {
    // Add session token to request
    if (config.token && data) {
        data.token = config.token;
    }
    const fullUrl = `https://${GetParentResourceName()}/${url}`;
    const payload = JSON.stringify(data);
    return $.post(fullUrl, payload).done(function(response) {
        // Request completed
    }).fail(function(error) {
        // Request failed
    });
}

function closeMenu() {
    $('#wipe-menu').fadeOut(300);
    post('closeMenu', {});
}

function showSection(section) {
    $('.search-section, .results-section, .vehicle-choice-section, .character-section, .vehicle-section, .confirmation-section, .logs-section').hide();
    $(`.${section}`).fadeIn(300);
}

function showLoading(show = true) {
    if (show) {
        $('.loading-spinner').fadeIn(200);
    } else {
        $('.loading-spinner').fadeOut(200);
    }
}

// Initialize translations
function initTranslations(translations) {
    $('#menu-title').text(translations.title);
    $('#search-title').text(translations.search);
    $('#label-firstname').text(translations.firstname);
    $('#label-lastname').text(translations.lastname);
    $('#label-phonenumber').text(translations.phonenumber);
    $('#btn-search-wipe').text(translations.wipe);
    $('#btn-search-restore').text(translations.restore);
    $('#results-title').text(translations.searchBtn);
    $('#btn-next-step').text(translations.nextStep || 'Next Step');
    $('#character-title').text(translations.selectChar);
    $('#character-subtitle').text(translations.vehTransfertTo);
    $('#vehicle-choice-title').text(translations.vehicleChoiceTitle || 'Vehicle Choice');
    $('#vehicle-choice-subtitle').text(translations.vehicleChoiceSubtitle || 'Choose what to do with the player vehicles.');
    $('#btn-vehicle-choice-transfer-keep').text(translations.vehicleActionTransferKeep || 'Transfer/Keep');
    $('#btn-vehicle-choice-delete').text(translations.vehicleActionDelete || 'Delete');
    $('#vehicle-title').text(translations.vehicleSelect || 'Select Vehicles to Transfer');
    $('#vehicle-subtitle').text(translations.vehicleSelectSubtitle || 'Only selected vehicles will be transferred.');
    $('#btn-cancel').text(translations.cancel);
    $('#btn-cancel-vehicle').text(translations.cancel);
    $('#btn-vehicle-transfer-target').text(translations.vehicleTransferTo || 'Transfer to');
    $('#btn-vehicle-keep').text(translations.vehicleKeep || 'Keep');
    $('#transfer-search-btn').text(translations.searchBtn || 'Search');
    $('#transfer-firstname').attr('placeholder', translations.firstname || 'Firstname');
    $('#transfer-lastname').attr('placeholder', translations.lastname || 'Lastname');
    $('#transfer-phone').attr('placeholder', translations.phonenumber || 'Phone number');
    $('#btn-confirm').text(translations.confirm);
    $('#btn-cancel-confirm').text(translations.cancel);
    // Logs translations
    $('#logs-title').text(translations.logsTitle || 'Player Logs');
    $('#logs-identifier-input').attr('placeholder', translations.logsSearchPlaceholder || 'Enter identifier...');
    $('#btn-search-logs').text(translations.logsSearchBtn || 'Search');
    $('#tab-main').text(config.safeWipeMode === false ? 'Wipe' : 'Wipe/Restore');
    $('#tab-logs').text(translations.logsTitle || 'Logs');
    
    if (config.safeWipeMode === false) {
        currentSearchType = 'wipe';
        $('#search-restore').hide();
        $('#search-wipe').removeClass('btn-secondary').addClass('btn-primary');
    } else {
        $('#search-restore').show();
    }
}

// Search player
function searchPlayer() {
    const firstname = $('#input-firstname').val().trim();
    const lastname = $('#input-lastname').val().trim();
    const phonenumber = $('#input-phonenumber').val().trim();

    if (!firstname && !lastname && !phonenumber) {
        return;
    }

    showLoading(true);

    post('searchPlayer', {
        firstname: firstname,
        lastname: lastname,
        phonenumber: phonenumber,
        searchType: currentSearchType
    }).then((response) => {
        showLoading(false);
        displayResults(response);
    });
}

// Display search results
function displayResults(results) {
    const $resultsList = $('#results-list');
    $resultsList.empty();
    $('#next-step-btn').prop('disabled', true);
    selectedPlayer = null;

    if (!results || !results.success || results.players.length === 0) {
        $resultsList.html(`
            <div class="no-results">
                <div class="no-results-icon">🔍</div>
                <p>${config.translations.noResults}</p>
            </div>
        `);
        showSection('results-section');
        return;
    }

    if (results.players.length > 10) {
        $resultsList.html(`
            <div class="no-results">
                <div class="no-results-icon">⚠️</div>
                <p>${results.players.length} ${config.translations.tooMany || 'Too many results'}</p>
            </div>
        `);
        showSection('results-section');
        return;
    }

    results.players.forEach(player => {
        const badge = '<span class="badge badge-active">ACTIVE</span>';
        
        const playerCard = $(`
            <div class="player-card" data-player='${JSON.stringify(player)}'>
                <div class="player-info">
                    <div class="player-name">
                        ${player.firstname || player.charinfo?.firstname || 'N/A'} 
                        ${player.lastname || player.charinfo?.lastname || ''}
                        ${badge}
                    </div>
                    <div class="player-details">
                        📞 ${player.phone || player.charinfo?.phone || 'N/A'} | 
                        🆔 ${player.citizenid || player.identifier || 'N/A'}
                    </div>
                </div>
            </div>
        `);

        playerCard.on('click', function() {
            $('.player-card').removeClass('selected');
            $(this).addClass('selected');
            selectedPlayer = JSON.parse($(this).attr('data-player'));
            $('#next-step-btn').prop('disabled', false);
        });

        $resultsList.append(playerCard);
    });

    showSection('results-section');
}

// Handle player selection
function handlePlayerSelection() {
    if (currentSearchType === 'restore') {
        showConfirmation();
        return;
    }

    vehicleAction = 'delete';
    transferTarget = null;
    selectedCharacter = null;
    characterList = [];

    if (!config.vehTransfert) {
        availableVehicles = [];
        selectedVehiclePlates = [];
        showConfirmation();
        return;
    }

    showVehicleChoice();
}

function showVehicleChoice() {
    if (currentSearchType !== 'wipe') {
        showConfirmation();
        return;
    }

    if (!config.vehTransfert) {
        availableVehicles = [];
        selectedVehiclePlates = [];
        showConfirmation();
        return;
    }

    showLoading(true);
    post('getPlayerVehicles', {
        playerData: selectedPlayer
    }).then((response) => {
        showLoading(false);
        if (response && response.success && response.vehicles && response.vehicles.length > 0) {
            // Collect all hashes for resolution
            const hashes = response.vehicles.map(v => String(v.model));
            
            // Call client callback to resolve hashes via GTA natives
            post('resolveVehicleHashes', {
                hashes: hashes
            }).then((hashResponse) => {
                if (hashResponse && hashResponse.success && hashResponse.resolved) {
                    // Map resolved names back to vehicles
                    response.vehicles.forEach((vehicle, index) => {
                        vehicle.model = hashResponse.resolved[index] || String(vehicle.model);
                    });
                }
                
                availableVehicles = response.vehicles;
                selectedVehiclePlates = response.vehicles.filter(v => (Number(v.value) || 0) === 0).map(v => v.plate);
                
                displayVehicleSelection(availableVehicles);
                showSection('vehicle-choice-section');
            }).catch((error) => {
                console.error('[character-manager] Error resolving hashes:', error);
                // Show vehicles with hashes if resolution fails
                availableVehicles = response.vehicles;
                selectedVehiclePlates = response.vehicles.filter(v => (Number(v.value) || 0) === 0).map(v => v.plate);
                displayVehicleSelection(availableVehicles);
                showSection('vehicle-choice-section');
            });
        } else {
            availableVehicles = [];
            selectedVehiclePlates = [];
            showConfirmation();
        }
    }).catch((error) => {
        console.error('[character-manager] Error in getPlayerVehicles:', error);
        showLoading(false);
        availableVehicles = [];
        selectedVehiclePlates = [];
        showConfirmation();
    });
}

// Display transfer target selection
function displayCharacterSelection(characters) {
    const $characterList = $('#character-list');
    $characterList.empty();

    if (!characters || characters.length === 0) {
        $characterList.html(`
            <div class="no-results">
                <div class="no-results-icon">🔍</div>
                <p>${config.translations.noResults}</p>
            </div>
        `);
        showSection('character-section');
        return;
    }

    characters.forEach((char, index) => {
        const charCard = $(`
            <div class="character-card" data-index="${index}">
                <div class="character-info">
                    <div class="character-name">
                        ${char.firstname || char.charinfo?.firstname || 'N/A'} 
                        ${char.lastname || char.charinfo?.lastname || ''}
                    </div>
                    <div class="character-details">
                        📞 ${char.phone || char.charinfo?.phone || 'N/A'} | 
                        🆔 ${char.citizenid || char.identifier || 'N/A'}
                    </div>
                </div>
            </div>
        `);

        charCard.on('click', function() {
            $('.character-card').css('border-color', 'rgba(255, 255, 255, 0.1)');
            $(this).css('border-color', '#667eea');
            transferTarget = characters[$(this).data('index')];
            selectedCharacter = transferTarget;
            vehicleAction = 'transfer';

            setTimeout(() => {
                showConfirmation();
            }, 300);
        });

        $characterList.append(charCard);
    });

    showSection('character-section');
}


function searchTransferTargets() {
    const firstname = $('#transfer-firstname').val().trim();
    const lastname = $('#transfer-lastname').val().trim();
    const phonenumber = $('#transfer-phone').val().trim();

    if (!firstname && !lastname && !phonenumber) {
        return;
    }

    showLoading(true);
    post('searchTransferTargets', {
        firstname: firstname,
        lastname: lastname,
        phonenumber: phonenumber,
    }).then((response) => {
        showLoading(false);

        if (!response || !response.success || !response.players) {
            displayCharacterSelection([]);
            return;
        }

        const currentId = selectedPlayer.citizenid || selectedPlayer.identifier;
        characterList = response.players.filter((char) => {
            return (char.citizenid || char.identifier) !== currentId;
        });

        displayCharacterSelection(characterList);
    });
}

function displayVehicleSelection(vehicles) {
    const $vehicleList = $('#vehicle-list');
    $vehicleList.empty();

    const countText = `${vehicles ? vehicles.length : 0} ${config.translations.vehicleCount || 'vehicle(s) found'}`;
    $('#vehicle-count').text(countText);

    if (!vehicles || vehicles.length === 0) {
        $vehicleList.html(`
            <div class="no-results">
                <div class="no-results-icon">🚗</div>
                <p>${config.translations.vehicleNone || 'No vehicles found'}</p>
            </div>
        `);
        showSection('vehicle-section');
        return;
    }

    vehicles.forEach((vehicle, index) => {
        const vehicleValue = Number(vehicle.value) || 0;
        const isPreSelected = vehicleValue === 0;
        const modelDisplay = vehicle.model ? String(vehicle.model).toUpperCase() : 'UNKNOWN';

        const vehicleCard = $(`
            <div class="vehicle-card" data-index="${index}">
                <label class="vehicle-checkbox-wrap">
                    <input type="checkbox" class="vehicle-checkbox" data-plate="${vehicle.plate}" ${isPreSelected ? 'checked' : ''}>
                    <span class="vehicle-checkmark"></span>
                </label>
                <div class="vehicle-info">
                    <div class="vehicle-line vehicle-plate-line">
                        <strong>🔖</strong> <span class="plate-value">${vehicle.plate}</span>
                    </div>
                    <div class="vehicle-line vehicle-model-line">
                        <strong>🚗</strong> <span class="model-value">${modelDisplay}</span>
                    </div>
                    <div class="vehicle-line vehicle-value-line">
                        <strong>💰</strong> <span class="value-display">${vehicleValue}$</span>
                    </div>
                </div>
            </div>
        `);

        vehicleCard.find('.vehicle-checkbox').on('change', function() {
            const plate = $(this).data('plate');
            if (this.checked) {
                if (!selectedVehiclePlates.includes(plate)) {
                    selectedVehiclePlates.push(plate);
                }
            } else {
                selectedVehiclePlates = selectedVehiclePlates.filter(p => p !== plate);
            }
        });

        $vehicleList.append(vehicleCard);
    });

    showSection('vehicle-section');
}

// Show confirmation dialog
function showConfirmation() {
    const $confirmDetails = $('#confirm-details');
    
    if (currentSearchType === 'wipe') {
        const hasVehicles = config.vehTransfert && availableVehicles.length > 0;

        let html = `
            <p><strong>${config.translations.wipeConfirm || 'Confirm Wipe'}</strong></p>
            <p>👤 ${selectedPlayer.firstname || selectedPlayer.charinfo?.firstname} ${selectedPlayer.lastname || selectedPlayer.charinfo?.lastname}</p>
            <p>📞 ${selectedPlayer.phone || selectedPlayer.charinfo?.phone}</p>
            <p>🆔 ${selectedPlayer.citizenid || selectedPlayer.identifier}</p>
        `;

        if (hasVehicles) {
            html += `
                <br>
                <p><strong>${config.translations.vehicleActionTitle || 'Vehicle action'}</strong></p>
                <p>🚗 ${selectedVehiclePlates.length}/${availableVehicles.length} ${config.translations.vehicleSelectedCount || 'selected vehicle(s)'}</p>
            `;

            if (vehicleAction === 'transfer') {
                if (transferTarget) {
                    html += `
                        <p><strong>${config.translations.vehTransfertTo || 'Vehicles will be transferred to'}:</strong></p>
                        <p>👤 ${transferTarget.firstname || transferTarget.charinfo?.firstname} ${transferTarget.lastname || transferTarget.charinfo?.lastname}</p>
                        <p>🆔 ${transferTarget.citizenid || transferTarget.identifier}</p>
                    `;
                }
            } else if (vehicleAction === 'keep') {
                html += `<p>${config.translations.vehicleKeepConfirm || 'Only selected vehicles will be kept; others will be deleted.'}</p>`;
            } else if (vehicleAction === 'delete') {
                html += `<p>${config.translations.vehicleDeleteConfirm || 'Vehicles will be deleted.'}</p>`;
            }
        }
        
        $confirmDetails.html(html);

        $('#confirm-action').prop('disabled', false);
    } else {
        const html = `
            <p><strong>${config.translations.restoreConfirm || 'Confirm Restore'}</strong></p>
            <p>👤 ${selectedPlayer.firstname || selectedPlayer.charinfo?.firstname} ${selectedPlayer.lastname || selectedPlayer.charinfo?.lastname}</p>
            <p>📞 ${selectedPlayer.phone || selectedPlayer.charinfo?.phone}</p>
            <p>🆔 ${selectedPlayer.citizenid || selectedPlayer.identifier}</p>
        `;
        $confirmDetails.html(html);
        $('#confirm-action').prop('disabled', false);
    }

    showSection('confirmation-section');
}

// Execute action
function executeAction() {
    showLoading(true);

    if (currentSearchType === 'wipe') {
        const hasVehicles = config.vehTransfert && availableVehicles.length > 0;

        if (hasVehicles && vehicleAction === 'transfer' && (!transferTarget || selectedVehiclePlates.length === 0)) {
            showLoading(false);
            return;
        }

        post('wipePlayer', {
            playerData: selectedPlayer,
            targetCharacter: transferTarget,
            selectedVehicles: selectedVehiclePlates,
            vehicleAction: vehicleAction
        }).then((response) => {
            showLoading(false);
            if (response.success) {
                resetMenu();
                setTimeout(() => closeMenu(), 1500);
            }
        });
    } else {
        if (config.safeWipeMode === false) {
            showLoading(false);
            return;
        }
        post('restorePlayer', {
            playerData: selectedPlayer
        }).then((response) => {
            showLoading(false);
            if (response.success) {
                resetMenu();
                setTimeout(() => closeMenu(), 1500);
            }
        });
    }
}

// Reset menu to initial state
function resetMenu() {
    selectedPlayer = null;
    selectedCharacter = null;
    characterList = [];
    availableVehicles = [];
    selectedVehiclePlates = [];
    vehicleAction = 'delete';
    transferTarget = null;
    $('#input-firstname').val('');
    $('#input-lastname').val('');
    $('#input-phonenumber').val('');
    $('#transfer-firstname').val('');
    $('#transfer-lastname').val('');
    $('#transfer-phone').val('');
    $('#results-list').empty();
    $('#next-step-btn').prop('disabled', true);
    $('.player-card').removeClass('selected');
    showSection('search-section');
}

// Event Listeners
$(document).ready(function() {
    // Close menu
    $('#close-menu').on('click', closeMenu);

    // ESC key to close
    $(document).on('keydown', function(e) {
        if (e.key === 'Escape') {
            closeMenu();
        }
    });

    // Search type buttons
    $('#search-wipe').on('click', function() {
        currentSearchType = 'wipe';
        $('#search-wipe').removeClass('btn-secondary').addClass('btn-primary');
        $('#search-restore').removeClass('btn-primary').addClass('btn-secondary');
        searchPlayer();
    });

    $('#search-restore').on('click', function() {
        if (config.safeWipeMode === false) {
            return;
        }
        currentSearchType = 'restore';
        $('#search-restore').removeClass('btn-secondary').addClass('btn-primary');
        $('#search-wipe').removeClass('btn-primary').addClass('btn-secondary');
        searchPlayer();
    });

    // Enter key to search
    $('#input-firstname, #input-lastname, #input-phonenumber').on('keypress', function(e) {
        if (e.key === 'Enter') {
            searchPlayer();
        }
    });

    // Cancel transfer target search
    $('#cancel-character').on('click', function() {
        showSection('vehicle-section');
    });

    // Confirm action
    $('#confirm-action').on('click', executeAction);

    // Cancel confirmation
    $('#cancel-action').on('click', function() {
        showSection('results-section');
    });

    $('#next-step-btn').on('click', function() {
        if (!selectedPlayer) {
            return;
        }

        if (currentSearchType === 'restore') {
            showConfirmation();
            return;
        }

        handlePlayerSelection();
    });

    // Tab switching
    $('.tab-btn').on('click', function() {
        const tab = $(this).data('tab');
        
        $('.tab-btn').removeClass('active');
        $(this).addClass('active');
        
        if (tab === 'main') {
            $('.search-section, .results-section, .character-section, .vehicle-section, .confirmation-section, .logs-section').hide();
            $('.search-section').fadeIn(300);
        } else if (tab === 'logs') {
            $('.search-section, .results-section, .character-section, .vehicle-section, .confirmation-section, .logs-section').hide();
            $('.logs-section').fadeIn(300);
        }
    });

    $('#cancel-vehicle').on('click', function() {
        showSection('vehicle-choice-section');
    });

    $('#vehicle-choice-transfer-keep').on('click', function() {
        vehicleAction = 'transfer';
        displayVehicleSelection(availableVehicles);
    });

    $('#vehicle-choice-delete').on('click', function() {
        vehicleAction = 'delete';
        transferTarget = null;
        selectedCharacter = null;
        showConfirmation();
    });

    $('#vehicle-transfer-target-btn').on('click', function() {
        vehicleAction = 'transfer';
        $('#character-list').empty();
        showSection('character-section');
    });

    $('#vehicle-keep-btn').on('click', function() {
        vehicleAction = 'keep';
        transferTarget = null;
        selectedCharacter = null;
        showConfirmation();
    });

    $('#transfer-search-btn').on('click', function() {
        searchTransferTargets();
    });

    $('#transfer-firstname, #transfer-lastname, #transfer-phone').on('keypress', function(e) {
        if (e.key === 'Enter') {
            searchTransferTargets();
        }
    });


    // Logs search
    $('#search-logs-btn').on('click', function() {
        const firstname = $('#logs-firstname-input').val().trim();
        const lastname = $('#logs-lastname-input').val().trim();
        const phone = $('#logs-phone-input').val().trim();
        
        // At least one field must be filled
        if (firstname || lastname || phone) {
            searchPlayerLogs({
                firstname: firstname,
                lastname: lastname,
                phone: phone
            });
        }
    });

    // Logs input Enter key (for all inputs)
    $('#logs-firstname-input, #logs-lastname-input, #logs-phone-input').on('keypress', function(e) {
        if (e.key === 'Enter') {
            const firstname = $('#logs-firstname-input').val().trim();
            const lastname = $('#logs-lastname-input').val().trim();
            const phone = $('#logs-phone-input').val().trim();
            
            if (firstname || lastname || phone) {
                searchPlayerLogs({
                    firstname: firstname,
                    lastname: lastname,
                    phone: phone
                });
            }
        }
    });
});

// Search Player Logs
function searchPlayerLogs(searchData) {
    showLoading(true);
    
    post('getPlayerLogs', searchData).then((response) => {
        showLoading(false);
        displayLogs(response);
    }).catch((error) => {
        showLoading(false);
        displayLogs({success: false, logs: []});
    });
}

// Display Logs
function displayLogs(response) {
    const $logsContainer = $('#logs-container');
    $logsContainer.empty();

    if (!response || !response.success || !response.logs || response.logs.length === 0) {
        $logsContainer.html(`
            <div class="logs-empty">
                <div class="logs-empty-icon">📋</div>
                <p>${config.translations?.logsNoLogs || 'No logs found'}</p>
            </div>
        `);
        return;
    }

    response.logs.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

    response.logs.forEach((log, index) => {
        const actionClass = log.action === 'wipe' ? 'wipe' : 'restore';
        const actionLabel = log.action === 'wipe'
            ? (config.translations.logsActionWipe || 'WIPE')
            : (config.translations.logsActionRestore || 'RESTORE');
        const timestamp = new Date(log.timestamp).toLocaleString();
        const logId = `log-${index}-${Date.now()}`;
        
        let detailsHTML = `
            <div class="log-detail">
                <div class="log-detail-label">${config.translations.logsIdentifier || 'Identifier'}</div>
                <div class="log-detail-value">${log.identifier || 'N/A'}</div>
            </div>
        `;

        if (log.citizenid) {
            detailsHTML += `
                <div class="log-detail">
                    <div class="log-detail-label">${config.translations.logsCitizenId || 'Citizen ID'}</div>
                    <div class="log-detail-value">${log.citizenid}</div>
                </div>
            `;
        }

        if (log.firstname || log.lastname) {
            detailsHTML += `
                <div class="log-detail">
                    <div class="log-detail-label">${config.translations.logsName || 'Name'}</div>
                    <div class="log-detail-value">${(log.firstname || '') + ' ' + (log.lastname || '')}</div>
                </div>
            `;
        }

        if (log.phone) {
            detailsHTML += `
                <div class="log-detail">
                    <div class="log-detail-label">Phone</div>
                    <div class="log-detail-value">${log.phone}</div>
                </div>
            `;
        }

        if (log.admin_identifier) {
            detailsHTML += `
                <div class="log-detail">
                    <div class="log-detail-label">${config.translations.logsAdmin || 'Admin'}</div>
                    <div class="log-detail-value">${log.admin_name || log.admin_identifier}</div>
                </div>
            `;
        }

        if (log.tables_count) {
            detailsHTML += `
                <div class="log-detail">
                    <div class="log-detail-label">${config.translations.logsTablesModified || 'Tables Modified'}</div>
                    <div class="log-detail-value">${log.tables_count}</div>
                </div>
            `;
        }

        // Parse and display vehicle transfer details
        let vehiclesHTML = '';
        if (log.vehicle_transferred) {
            let vehiclesList = [];
            
            // Try to parse details if it's JSON string
            if (log.details && typeof log.details === 'string') {
                try {
                    vehiclesList = JSON.parse(log.details);
                    if (!Array.isArray(vehiclesList)) {
                        vehiclesList = [];
                    }
                } catch (e) {
                    vehiclesList = [];
                }
            }

            let transferInfo = '<div class="log-transfer-info">';
            
            if (log.transfer_target_name) {
                transferInfo += `<div class="transfer-target">👤 ${config.translations.logsTransferredTo || 'Transferred to'}: <strong>${log.transfer_target_name}</strong></div>`;
            }
            
            transferInfo += `<div class="vehicles-count">🚗 ${vehiclesList.length} ${config.translations.logsVehiclesTransferred || 'vehicle(s) transferred'}</div>`;
            transferInfo += '</div>';
            
            if (vehiclesList && vehiclesList.length > 0) {
                vehiclesHTML = `
                    <div class="log-vehicles-section">
                        ${transferInfo}
                        <div class="vehicles-toggle" data-target="${logId}-vehicles">
                            <span class="toggle-icon">▼</span>
                            <span class="toggle-text">${config.translations.logsShowVehicleDetails || 'Show Vehicle Details'}</span>
                        </div>
                        <div class="vehicle-list" id="${logId}-vehicles" style="display: none;">
                `;
                
                vehiclesList.forEach(vehicle => {
                    vehiclesHTML += `
                        <div class="vehicle-item">
                            <div class="vehicle-plate">🔖 ${vehicle.plate || 'N/A'}</div>
                            <div class="vehicle-model">📋 ${vehicle.model || (config.translations.logsUnknown || 'Unknown')}</div>
                        </div>
                    `;
                });
                
                vehiclesHTML += `
                        </div>
                    </div>
                `;
            } else if (transferInfo) {
                vehiclesHTML = `<div class="log-vehicles-section">${transferInfo}</div>`;
            }
        }

        const logHTML = `
            <div class="log-entry action-${actionClass}">
                <div class="log-header">
                    <span class="log-action ${actionClass}">${actionLabel}</span>
                    <span class="log-timestamp">${timestamp}</span>
                </div>
                <div class="log-details">
                    ${detailsHTML}
                </div>
                ${vehiclesHTML}
            </div>
        `;

        $logsContainer.append(logHTML);
    });

    // Add click handlers for vehicle toggle
    $logsContainer.on('click', '.vehicles-toggle', function() {
        const target = $(this).data('target');
        const $vehicleList = $(`#${target}`);
        const $icon = $(this).find('.toggle-icon');
        
        $vehicleList.slideToggle(300);
        $icon.toggleClass('open');
    });
}

// NUI Message Handler
window.addEventListener('message', function(event) {
    const data = event.data;

    switch(data.action) {
        case 'openMenu':
            config = data.config;
            initTranslations(config.translations);
            resetMenu();
            $('#wipe-menu').fadeIn(300);
            break;
        
        case 'closeMenu':
            $('#wipe-menu').fadeOut(300);
            break;
    }
});
