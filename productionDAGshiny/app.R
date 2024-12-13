library(shiny)
library(tidyverse)
library(ggdag)
library(dagitty)
library(DiagrammeR)
library(DiagrammeRsvg)
library(rsvg)
library(shinydashboard)

library(shinyjs)
library(bslib)
library(shinyWidgets)

library(shinytest2)


# Source the module files
source("R/helpers.R")

source("displayNodes/ui.R")
source("displayNodes/server.R")
source("openBackDoorPathsDAG/ui.R")
source("openBackDoorPathsDAG/server.R")
source("nameModal/server.R")
source("RCode/server.R")

# Turn on for production
options(warn = -1)

# Define Theme ------------------------------------------------------------
# appTheme <- bs_theme(
#   version = 5,
#   bg = "#ffffff",
#   fg = "#000000",
#   primary = "#BDDD21",
#   secondary = "#462A79",
#   success = "#423F85",
#   info = "#39548C",
#   warning = "#218E8B",
#   danger = "#61CA5F",
#   base_font = font_google("Roboto"),
#   code_font = font_google("JetBrains Mono"),
#   heading_font = font_google("Lato")
# )
library(shiny)
library(bslib)
library(shinyjs)


# Define theme
appTheme <- bs_theme(
    bg = "#ffffff",
    fg = "#000000",
    primary = "#BDDD21",
    secondary = "#462A79",
    success = "#423F85",
  base_font = font_google("Roboto"),
  code_font = font_google("JetBrains Mono"),
  heading_font = font_google("Lato")
)
# 
# # Define theme
# appTheme <- bs_theme(
#   bg = "#fff",
#   fg = "#073660",
#   primary = "#2FB9AB",
#   secondary = "#1C7986",
#   success = "#F04F24",
#   base_font = font_google("Roboto"),
#   code_font = font_google("JetBrains Mono"),
#   heading_font = font_google("Lato")
# )

# Define UI
ui <- page_navbar(
  theme = appTheme,
  title = div(
    style = "display: flex; align-items: center; justify-content: space-between; width: 100%;",
    span("DAGagramR v0.1.0"),
    tags$img(src = "CCSlogo.png", height = "35px", style = "margin-right: 10px; margin-left: 10px;")
  ),
  
  # Include shinyjs for JavaScript functionality
  useShinyjs(),
  
  # Main content layout with two cards: a flexible-width sidebar card and a flexible main content card
  nav_panel(
    "Main",
    fluidRow(
      column(
        width = 3,  # Flexible width for the sidebar
        style = "max-width: 300px;",
        card(
          full_screen = TRUE,
          displayNodesUI("displayNodes")
        )
      ),
      column(
        width = 9,  # Flexible width for main content
        card(
          full_screen = TRUE,
          fluidRow(
            column(1, actionButton("refreshLayout", NULL, icon = icon("refresh"))),
            column(6, materialSwitch(
              inputId = "showBackdoor",
              label = "Show Open Backdoor Paths",
              status = "primary",
              right = FALSE
            ),
            uiOutput("effectModifierSwitch")
            )
          ),
          uiOutput("legend"),
          uiOutput("graph")
        )
      )
    )
  ),
  
  # Additional tab
  nav_panel("User Guide", div(p("Pending"))),
  
  # Downloads dropdown menu with downloadButton for each item
  nav_menu(
    "Downloads",
    nav_item(downloadButton("dag", "Download DAG Image", icon = icon("download"))),
    nav_item(downloadButton("backdoorDag", "Download Backdoor DAG", icon = icon("download"))),
    nav_item(downloadButton("legendDownload", "Download DAG Legend", icon = icon("download"))),
    nav_item(actionButton("downloadRCode", "Copy R-Code to Clipboard", icon = icon("copy")))
  )
)

server <- function(input, output, session) {
  
  # Show initial modal
  observe({
    showModal(modalDialog(
      title = "Welcome to DAGagramR",
      p("Please enter the initial settings for your DAG."),
      textInput("treatmentName", "Treatment Name", ""),
      textInput("responseName", "Response Name", ""),
      checkboxInput("transportability", "Enable Transportability?", FALSE),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("setNames", "Start")
      )
    ))
  })
  
  # Handle modal form submission
  observeEvent(input$setNames, {
    if (CheckNameInput(input$treatmentName)$isValid & CheckNameInput(input$responseName)$isValid) {
      removeModal()
      
      # Set up reactive values for inputs
      treatment <- reactiveVal(input$treatmentName)
      response <- reactiveVal(input$responseName)
      highlightedPathList <- reactiveVal(NULL)
      isTransportability <- reactiveVal(input$transportability)
      
      if (isTransportability()) {
        toDataStorage <- reactiveValues(
          data = data.frame(
            name = I(c(response(), treatment(), "Participation")),
            to = I(c(NA, response(), NA)),
            unmeasured = FALSE,
            conditioned = FALSE,
            base = TRUE,
            effectModifier = FALSE
          )
        )
        
        # Add the effect modifier switch
        output$effectModifierSwitch <- renderUI(
          materialSwitch(
            inputId = "showEffectModifiers",
            label = "Show Effect Modifiers",
            status = "primary",
            right = FALSE
          )
        )
        
      } else {
        toDataStorage <- reactiveValues(
          data = data.frame(
            name = I(c(response(), treatment())),
            to = I(c(NA, response())),
            unmeasured = FALSE,
            conditioned = FALSE,
            base = TRUE,
            effectModifier = FALSE
          )
        )
      }
      
      dagDownloads <- reactiveValues(
        dag = NULL,
        backdoorDag = NULL,
        legend = NULL,
        RCode = "This is your R code" # Replace this with your actual R code to be copied
      )
      
      effectModifierShow <- reactiveVal(FALSE)
      openDAGUI("openDAG")
      backdoorShow <- reactiveVal(FALSE)
      layout <- reactiveVal("kk")
      
      observe({
        openDAGUI("openDAG")
        backdoorShow(input$showBackdoor)
        if (!is.null(input$showEffectModifiers)){
          effectModifierShow(input$showEffectModifiers)
        }

        output$graph <- renderUI({
          openDAGUI("openDAG")
        })
      })
      
      observeEvent(input$refreshLayout, {
        if (layout() == "kk") {
          layout("tree")
        } else if (layout() == "tree") {
          layout("circle")
        } else {
          layout("kk")
        }
      })
      
      callModule(displayNodesServer, "displayNodes",
                 toDataStorage, treatment, response, highlightedPathList)
      callModule(openDAGServer, "openDAG", toDataStorage,
                 treatment, response, highlightedPathList, isTransportability,
                 dagDownloads, backdoorShow, effectModifierShow, layout)
      callModule(RCodeServer, "RCode", toDataStorage, dagDownloads)
      
      # Handle download buttons
      output$dag <- downloadHandler(
        filename = function() { paste0("dag", ".png") },
        content = function(file) {
          export_graph(dagDownloads$dag, file_name = file, file_type = "png", width = 4000, height = 3000)
        }
      )
      
      output$backdoorDag <- downloadHandler(
        filename = function() { paste0("backdoorDag", ".png") },
        content = function(file) {
          export_graph(dagDownloads$backdoorDag, file_name = file, file_type = "png", width = 4000, height = 3000)
        }
      )
      
      output$legendDownload <- downloadHandler(
        filename = function() { paste0("dagLegend", ".png") },
        content = function(file) {
          export_graph(dagDownloads$legend, file_name = file, file_type = "png", width = 4000, height = 3000)
        }
      )
      
      observeEvent(input$downloadRCode, {
        session$sendCustomMessage("copyToClipboard", dagDownloads$RCode)
      })
      
    } else {
      output$nameError <- renderUI({
        p("The names must follow the naming convention",
          id = "nameError", class = "errorMessage")
      })
      runjs("setTimeout(function() { $('#nameError').fadeOut(); }, 3000);")
    }
  })
}

shinyApp(ui = ui, server = server)


# appTheme = bs_theme(
#   bg = "#fff",
#   fg = "#073660",
#   primary = "#2FB9AB",
#   secondary = "#1C7986",
#   success = "#F04F24",
#   base_font = font_google("Roboto"),
#   code_font = font_google("JetBrains Mono"),
#   heading_font = font_google("Lato")
# )
# 
# 
# ui <- dashboardPage(
#   dashboardHeader(title = "DAGagramR",
#                   dropdownMenu(type = "notifications",
#                                icon = icon("download"),
#                                notificationItem(
#                                  text = HTML('<span id="downloadDAG">Download the DAG Image </span>'),
#                                  icon = icon("download")
#                                ),
#                                notificationItem(
#                                  text = HTML('<span id="downloadBackDoor">Download the Backdoor DAG</span>'),
#                                  icon = icon("download")
#                                ),
#                                notificationItem(
#                                  text = HTML('<span id="downloadLegend">Downoad the DAG Legend</span>'),
#                                  icon = icon("download")
#                                ),
#                                notificationItem(
#                                  text = HTML('<span id="downloadRCode">Copy R-Code to Clipboard</span>'),
#                                  icon = icon("copy")
#                                )
#                   )
#                   
#   ),
#   dashboardSidebar(
#     displayNodesUI("displayNodes"),
#     
#     tags$img(
#       src = convertImgToDataUrl("img/longCSSlogo.png"),
#       width = 200,
#       alt = "CSS logo"
#     ),
#     
#     # Hidden dag download button
#     div(
#       downloadButton("dag", "dag", style = "margin-left: 10px !important;
#                                             margin: 5px !important;
#                                             visibility: hidden;"),
#       # Hidden backdoor download button
#       downloadButton("backdoorDag", "backdoorDag", style = "margin-left: 10px !important;
#                                                             margin: 5px !important;
#                                                             visibility: hidden;"),
#       # Hidden legend download button
#       downloadButton("legendDownload", "legend", style = "margin-left: 10px !important;
#                                                   margin: 5px !important;
#                                                   visibility: hidden;"),
#       downloadButton("RCode", "RCode", style = "display: none;")
#     )
# 
#   ),
#   dashboardBody(
#     shinyjs::useShinyjs(),
#     #Script to handle download buttons to shiny observe elements
#     tags$script(HTML("
#       $(document).on('shiny:connected', function() {
#         $('#downloadDAG').on('click', function() {
#           Shiny.onInputChange('downloadDAG_clicked', new Date());
#         });
#         $('#downloadBackDoor').on('click', function() {
#           Shiny.onInputChange('downloadBackdoor_clicked', new Date());
#         });
#         $('#downloadLegend').on('click', function() {
#           Shiny.onInputChange('downloadLegend_clicked', new Date());
#         });
#         $('#downloadRCode').on('click', function() {
#           Shiny.onInputChange('downloadRCode_clicked', new Date());
#         });
#       })
#       
#       Shiny.addCustomMessageHandler('txt', function (txt) {
#                 navigator.clipboard.writeText(txt);
#             });
#     ")),
#     tags$head(
#       tags$link(rel = "stylesheet", type = "text/css", href = "styles.css")
#     ),
#     fluidRow(
#       column(1,
#         actionButton("refreshLayout", NULL, icon = icon("refresh")),
#       ),
#       column(6,
#         materialSwitch(
#           inputId = "showBackdoor",
#           label = "Show Open Backdoor Paths", 
#           status = "primary",
#           right = FALSE
#         )
#       )
#     ),
#     
#     uiOutput("legend"),
#     uiOutput("graph")
#   )
# )
# 
# 
# server <- function(input, output, session) {
#   callModule(nameModalServer, "nameModal")
#   
#   observe({
#     runjs('document.querySelector(".dropdown-menu li.header").innerText = "Click the text to download";')
#   })
#   
#   observeEvent(input$setNames, {
#     if (CheckNameInput(input$treatmentName)$isValid &
#         CheckNameInput(input$responseName)$isValid) {
#       removeModal()
#       
#       # Set up Shared Resources
#       treatment <- reactiveVal(input$treatmentName)
#       response <- reactiveVal(input$responseName)
#       highlightedPathList <- reactiveVal(NULL)
#       isTransportability <- reactiveVal(input$transportability)
#       
#       if(isTransportability()) {
#         toDataStorage <- reactiveValues(
#           data = data.frame(
#             name = I(c(response(), treatment(), "Participation")),
#             to = I(c(NA, response(), NA)),
#             unmeasured = FALSE,
#             conditioned = FALSE,
#             base = TRUE
#           )
#         )
#       } else {
#         toDataStorage <- reactiveValues(
#           data = data.frame(
#             name = I(c(response(), treatment())),
#             to = I(c(NA, response())),
#             unmeasured = FALSE,
#             conditioned = FALSE,
#             base = TRUE
#           )
#         )
#       }
#       
#       dagDownloads <- reactiveValues(
#         dag = NULL,
#         backdoorDag = NULL,
#         legend = NULL,
#         RCode = NULL
#       )
#       
#       openDAGUI("openDAG")
# 
#       backdoorShow <- reactiveVal(FALSE)
#       layout <- reactiveVal("kk")
# 
#       observe({
#         openDAGUI("openDAG")
# 
#         backdoorShow(input$showBackdoor)
#         
#         output$graph <- renderUI({
#           openDAGUI("openDAG")
#         })
#         
#       })
#       
#       
#       # Layout choices: "nicely", "kk", "tree", "fr", "circle"
#       observeEvent(input$refreshLayout, {
#         if(layout() == "kk") {
#           layout("tree")
#         } else if (layout() == "tree") {
#           layout("circle")
#         } else {
#           layout("kk")
#         }
#       })
#       
#       # Run these inside the observe because they are dependent on toDataStorage
#       callModule(displayNodesServer, "displayNodes",
#                  toDataStorage, treatment, response, highlightedPathList)
#       callModule(openDAGServer, "openDAG", toDataStorage,
#                  treatment, response, highlightedPathList, isTransportability,
#                  dagDownloads, backdoorShow, layout)
#       callModule(RCodeServer, "RCode", toDataStorage, dagDownloads)
#       
#       # Handle the download Buttons 
#       output$dag <- downloadHandler(
#         filename = function() {
#           paste0("dag", ".png")
#         },
#         content = function(file) {
#           export_graph(
#             dagDownloads$dag,
#             file_name = file,
#             file_type = "png",
#             width = 4000,
#             height = 3000
#           )
#         }
#       )
#       
#       observeEvent(input$downloadDAG_clicked, {
#         print("Downloaded DAG")
#         # Trigger the hidden download button
#         click("dag")
#       })
#       
#       output$backdoorDag <- downloadHandler(
#         filename = function() {
#           paste0("backdoorDag", ".png")
#         },
#         content = function(file) {
#           export_graph(
#             dagDownloads$backdoorDag,
#             file_name = file,
#             file_type = "png",
#             width = 4000,
#             height = 3000
#           )
#         }
#       )
#       
#       
#       observeEvent(input$downloadBackdoor_clicked, {
#         print("Downloaded BackdoorDag")
#         click("backdoorDag")
#       })
#       
#       output$legendDownload <- downloadHandler(
#         filename = function() {
#           paste0("dagLegend", ".png")
#         },
#         content = function(file) {
#           export_graph(
#             dagDownloads$legend,
#             file_name = file,
#             file_type = "png",
#             width = 4000,
#             height = 3000
#           )
#         }
#       )
#       
#       observeEvent(input$downloadLegend_clicked, {
#         print("Downloaded Legend")
#         click("legendDownload")
#       })
#       
#       observeEvent(input$downloadRCode_clicked, {
#         # Show modal with message
#         showModal(modalDialog(
#           "R code copied to clipboard",
#           easyClose = TRUE
#         ))
#         
#         session$sendCustomMessage("txt", dagDownloads$RCode)
#       })
#       
#     } else {
#       output$nameError <- renderUI({
#         p("The names must follow the naming convention",
#           id = "nameError", class = "errorMessage")
#       })
#       # Hide after 5 seconds
#       runjs("setTimeout(function() { $('#nameError').fadeOut(); }, 3000);")
#     }
#   })
# }
# 
# 
# set.seed(128)
# 
# shinyApp(ui = ui, server = server)