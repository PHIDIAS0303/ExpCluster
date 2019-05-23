--- This file is used to require all the different elements of the gui module
-- each module has an outline here but for more details see their seperate files in ./gui

local Gui = require 'expcore.gui.core'
--[[
    Gui._prototype_factory(tbl) --- Used internally to create new prototypes for element defines
    Gui._event_factory(name) --- Used internally to create event handler adders for element defines
    Gui._store_factory(callback) --- Used internally to create store adders for element defines
    Gui._sync_store_factory(callback) --- Used internally to create synced store adders for element defines
    Gui._define_factory(prototype) --- Used internally to create new element defines from a class prototype

    Gui._prototype:uid() --- Gets the uid for the element define
    Gui._prototype:debug_name(name) --- Sets a debug alias for the define
    Gui._prototype:set_caption(caption) --- Sets the caption for the element define
    Gui._prototype:set_tooltip(tooltip) --- Sets the tooltip for the element define
    Gui._prototype:on_element_update(callback) --- Add a hander to run on the general value update event, different classes will handle this event differently

    Gui._prototype:set_pre_authenticator(callback) --- Sets an authenticator that blocks the draw function if check fails
    Gui._prototype:set_post_authenticator(callback) --- Sets an authenticator that disables the element if check fails
    Gui._prototype:draw_to(element) --- Draws the element using what is in the draw_data table, allows use of authenticator if present, registers new instances if store present
    Gui.draw(name,element) --- Draws a copy of the element define to the parent element, see draw_to

    Gui._prototype:add_store(categorize) --- Adds a store location for the define that will save the state of the element, categorize is a function that returns a string
    Gui._prototype:add_sync_store(location,categorize) --- Adds a store location for the define that will sync between games, categorize is a function that returns a string
    Gui._prototype:on_store_update(callback) --- Adds a event callback for when the store changes are other events are not gauenteted to be raised
    Gui.player_store(element) --- A categorize function to be used with add_store, each player has their own value
    Gui.force_store(element) --- A categorize function to be used with add_store, each force has its own value
    Gui.surface_store(element) --- A categorize function to be used with add_store, each surface has its own value

    Gui._prototype:get_store(category) --- Gets the value in this elements store, category needed if categorize function used
    Gui._prototype:set_store(category,value) --- Sets the value in this elements store, category needed if categorize function used
    Gui.get_store(name,category) --- Gets the value that is stored for a given element define, category needed if categorize function used
    Gui.set_store(name,category,value) --- Sets the value stored for a given element define, category needed if categorize function used

    Gui.toggle_enable(element) --- Will toggle the enabled state of an element
    Gui.toggle_visible(element) --- Will toggle the visiblity of an element
]]

local Instances = require 'expcore.gui.instances'
Gui.new_instance_group = Instances.registers
Gui.get_instances = Instances.get_elements
Gui.add_instance = Instances.get_elements
Gui.update_instances = Instances.apply_to_elements
Gui.classes.instances = Instances

local Button = require 'expcore.gui.buttons'
Gui.new_button = Button.new_button
Gui.classes.button = Button
--[[
    Button.new_button(name) --- Creates a new button element define

    Button._prototype:on_click(player,element) --- Registers a handler for when the button is clicked
    Button._prototype:on_left_click(player,element) --- Registers a handler for when the button is clicked with the left mouse button
    Button._prototype:on_right_click(player,element) --- Registers a handler for when the button is clicked with the right mouse button

    Button._prototype:set_sprites(sprite,hovered_sprite,clicked_sprite) --- Adds sprites to a button making it a spirte button
    Button._prototype:set_click_filter(filter,...) --- Adds a click / mouse button filter to the button
    Button._prototype:set_key_filter(filter,...) --- Adds a control key filter to the button
]]

local Checkbox = require 'expcore.gui.checkboxs'
Gui.new_checkbox = Checkbox.new_checkbox
Gui.new_radiobutton = Checkbox.new_radiobutton
Gui.new_radiobutton_option_set = Checkbox.new_option_set
Gui.draw_option_set = Checkbox.draw_option_set
Gui.classes.checkbox = Checkbox
--[[
    Checkbox.new_checkbox(name) --- Creates a new checkbox element define
    Checkbox._prototype_checkbox:on_element_update(callback) --- Registers a handler for when an element instance updates
    Checkbox._prototype_checkbox:on_store_update(callback) --- Registers a handler for when the stored value updates

    Checkbox.new_radiobutton(name) --- Creates a new radiobutton element define
    Checkbox._prototype_radiobutton:on_element_update(callback) --- Registers a handler for when an element instance updates
    Checkbox._prototype_radiobutton:on_store_update(callback) --- Registers a handler for when the stored value updates
    Checkbox._prototype_radiobutton:add_as_option(option_set,option_name) --- Adds this radiobutton to be an option in the given option set (only one can be true at a time)

    Checkbox.new_option_set(name,callback,categorize) --- Registers a new option set that can be linked to radiobutotns (only one can be true at a time)
    Checkbox.draw_option_set(name,element) --- Draws all radiobuttons that are part of an option set at once (Gui.draw will not work)

    Checkbox.reset_radiobutton(element,exclude,recursive) --- Sets all radiobutotn in a element to false (unless excluded) and can act recursivly
]]

local Dropdown = require 'expcore.gui.dropdown'
Gui.new_dropdown = Dropdown.new_dropdown
Gui.new_list_box = Dropdown.new_list_box
Gui.classes.dropdown = Dropdown
--[[
    Dropdown.new_dropdown(name) --- Creates a new dropdown element define
    Dropdown.new_list_box(name) --- Creates a new list box element define

    Dropdown._prototype:on_element_update(callback) --- Registers a handler for when an element instance updates
    Dropdown._prototype:on_store_update(callback) --- Registers a handler for when the stored value updates

    Dropdown._prototype:new_static_options(options,...) --- Adds new static options to the dropdown which will trigger the general callback
    Dropdown._prototype:new_dynamic_options(callback) --- Adds a callback which should return a table of values to be added as options for the dropdown (appended after static options)
    Dropdown._prototype:add_option_callback(option,callback) --- Adds a case specific callback which will only run when that option is selected (general case still triggered)

    Dropdown.select_value(element,value) --- Selects the option from a dropdown or list box given the value rather than key
    Dropdown.get_selected_value(element) --- Returns the currently selected value rather than index
]]

local Slider = require 'expcore.gui.slider'
Gui.new_slider = Slider.new_slider
Gui.classes.slider = Slider
--[[
    Slider.new_slider(name) --- Creates a new slider element define

    Slider._prototype:on_element_update(callback) --- Registers a handler for when an element instance updates
    Slider._prototype:on_store_update(callback) --- Registers a handler for when the stored value updates

    Slider._prototype:set_range(min,max) --- Sets the range of a slider, if not used will use default values for a slider
    Slider._prototype:draw_label(element) --- Draws a new label and links its value to the value of this slider, if no store then it will only show one value per player
    Slider._prototype:enable_auto_draw_label(state) --- Enables auto draw of the label, the label will share the same parent element as the slider
]]

local Text = require 'expcore.gui.text'
Gui.new_text_filed = Text.new_text_field
Gui.new_text_box = Text.new_text_box
Gui.classes.text = Text
--[[
    Text.new_text_field(name) --- Creates a new text field element define
    Text._prototype_field:on_element_update(callback) --- Registers a handler for when an element instance updates
    Text._prototype_field:on_store_update(callback) --- Registers a handler for when the stored value updates

    Text.new_text_box(name) --- Creates a new text box element define
    Text._prototype_field:on_element_update(callback) --- Registers a handler for when an element instance updates
    Text._prototype_field:on_store_update(callback) --- Registers a handler for when the stored value updates
    Text._prototype_box:set_selectable(state) --- Sets the text box to be selectable
    Text._prototype_box:set_word_wrap(state) --- Sets the text box to have word wrap
    Text._prototype_box:set_read_only(state) --- Sets the text box to be read only
]]

local ElemButton = require 'expcore.gui.elem-button'
Gui.new_elem_button = ElemButton.new_elem_button
Gui.classes.elem_button = ElemButton
--[[
    ElemButton.new_elem_button(name) --- Creates a new elem button element define

    ElemButton._prototype:on_element_update(callback) --- Registers a handler for when an element instance updates
    ElemButton._prototype:on_store_update(callback) --- Registers a handler for when the stored value updates

    ElemButton._prototype:set_type(type) --- Sets the type of the elem button, the type is required so this must be called at least once
    ElemButton._prototype:set_default(value) --- Sets the default value for the elem button, this may be a function or a string
]]

local Toolbar = require 'expcore.gui.toolbar'
Gui.new_toolbar_button = Toolbar.new_button
Gui.add_button_to_toolbar = Toolbar.add_button
Gui.update_toolbar = Toolbar.update
Gui.classes.toolbar = Toolbar
--[[
    Toolbar.new_button(name) --- Adds a new button to the toolbar
    Toolbar.add_button(button) --- Adds an existing buttton to the toolbar
    Toolbar.update(player) --- Updates the player's toolbar with an new buttons or expected change in auth return
]]

local LeftFrames = require 'expcore.gui.left'
Gui.get_left_frame_flow = LeftFrames.get_flow
Gui.toggle_left_frame = LeftFrames.toggle_frame
Gui.new_left_frame = LeftFrames.new_frame
Gui.classes.left_frames = LeftFrames
--[[
    LeftFrames.get_flow(player) --- Gets the left frame flow for a player
    LeftFrames.get_frame(name,player) --- Gets one frame from the left flow by its name
    LeftFrames.get_open(player) --- Gets all open frames for a player, if non are open it will remove the close all button
    LeftFrames.toggle_frame(name,player,state) --- Toggles the visiblty of a left frame, or sets its visiblty state

    LeftFrames.new_frame(permision_name) --- Creates a new left frame define
    LeftFrames._prototype:set_open_by_default(state) --- Sets if the frame is visible when a player joins, can also be a function to return a boolean
    LeftFrames._prototype:get_frame(player) --- Gets the frame for this define from the left frame flow
    LeftFrames._prototype:is_open(player) --- Returns if the player currently has this define visible
    LeftFrames._prototype:toggle(player) --- Toggles the visiblty of the left frame

    LeftFrames._prototype:update(player) --- Updates the contents of the left frame, first tries update callback, oter wise will clear and redraw
    LeftFrames._prototype:update_all(update_offline) --- Updates the frame for all players, see update
    LeftFrames._prototype:redraw(player) --- Redraws the frame by calling on_draw, will always clear the frame
    LeftFrames._prototype:redraw_all(update_offline) --- Redraws the frame for all players, see redraw

    LeftFrames._prototype:event_handler(action) --- Creates an event handler that will trigger one of its functions, use with Event.add
]]

local CenterFrames = require 'expcore.gui.center'
Gui.get_center_flow = CenterFrames.get_flow
Gui.toggle_left_frame = CenterFrames.toggle_frame
Gui.draw_center_frame = CenterFrames.draw_frame
Gui.redraw_center_frame = CenterFrames.redraw_frames
Gui.new_center_frame = CenterFrames.new_frame
Gui.classes.center_frames = CenterFrames
--[[
    CenterFrames.get_flow(player) --- Gets the center flow for a player
    CenterFrames.clear_flow(player) --- Clears the center flow for a player
    CenterFrames.draw_frame(player,name) --- Draws the center frame for a player, if already open then will do nothing
    CenterFrames.redraw_frame(player,name) --- Draws the center frame for a player, if already open then will destory it and redraw
    CenterFrames.toggle_frame(player,name,state) --- Toggles if the frame is currently open or not, will open if closed and close if open

    CenterFrames.new_frame(permision_name) --- Sets the frame to be the current active gui when opened and closes all other frames
    CenterFrames._prototype:set_auto_focus(state) --- Sets the frame to be the current active gui when opened and closes all other frames
    CenterFrames._prototype:draw_frame(player) --- Draws this frame to the player, if already open does nothing (will call on_draw to draw to the frame)
    CenterFrames._prototype:redraw_frame(player) --- Draws this frame to the player, if already open it will remove it and redraw it (will call on_draw to draw to the frame)
    CenterFrames._prototype:toggle_frame(player) --- Toggles if the frame is open, if open it will close it and if closed it will open it
    CenterFrames._prototype:event_handler(action) --- Creates an event handler that will trigger one of its functions, use with Event.add
]]

return Gui