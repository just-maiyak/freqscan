// IMPORTS ------------------------------------------------

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp

// MAIN    ------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

// MODEL   ------------------------------------------------

type Model {
  Model(
    total_questions: Int,
    answers: Answers,
    next_questions: List(#(Question, Answers)),
    previous_questions: List(#(Question, Answers)),
    current_page: Page,
    field_content: Option(String),
    result: Option(Frequency),
  )
}

type Playlist {
  Playlist(deezer: String, spotify: String, apple: String, youtube: String)
}

type Frequency {
  Frequency(
    frequency: Station,
    name: String,
    verbatims: List(String),
    tags: List(String),
    artists: List(String),
    playlist: Playlist,
    image: String,
  )
}

type Questionnaire {
  Questionnaire(questions: List(#(Question, Answers)))
}

type Question {
  Question(question_id: String, question: String)
}

type Answers =
  List(Choice)

type Choice {
  PromptChoice(answer: String, station: Station)
  CustomChoice(question: Question, answer: String)
}

type Station {
  Slower
  Slow
  Fast
  Faster
}

type Page {
  Home
  Prompt(question: Question, choices: Answers)
  LoadingResult
  Result
}

fn init(_) -> #(Model, Effect(Msg)) {
  let questionnaire: Questionnaire = load_questionnaire()
  let model: Model =
    Model(
      total_questions: list.length(questionnaire.questions),
      answers: [],
      next_questions: list.shuffle(questionnaire.questions),
      previous_questions: [],
      current_page: Home,
      field_content: None,
      result: None,
    )

  #(model, effect.none())
}

fn choice_to_json(choice: Choice) -> json.Json {
  case choice {
    CustomChoice(question:, answer:) ->
      json.object([
        #("question_id", json.string(question.question_id)),
        #("answer", json.string(answer)),
      ])
    _ -> json.int(1)
  }
}

fn fetch_frequency(
  answers: List(Choice),
  _language: String,
  on_response handle_response: fn(Result(Frequency, rsvp.Error)) -> Msg,
) -> Effect(Msg) {
  let api_url = "https://freqgen.yefimch.uk/predict"
  let decoder = frequency_decoder()
  let handler = rsvp.expect_json(decoder, handle_response)
  let body =
    json.object([#("answers", json.array(answers, of: choice_to_json))])

  rsvp.post(api_url, body, handler)
}

fn station_decoder() -> Decoder(Station) {
  use freq_string <- decode.then(decode.string)
  case freq_string {
    "slower" -> decode.success(Slower)
    "slow" -> decode.success(Slow)
    "fast" -> decode.success(Fast)
    "faster" -> decode.success(Faster)
    _ -> decode.failure(Fast, "Could not parse frequency")
  }
}

fn playlist_decoder() -> Decoder(Playlist) {
  use deezer <- decode.field("deezer", decode.string)
  use spotify <- decode.field("spotify", decode.string)
  use apple <- decode.field("apple", decode.string)
  use youtube <- decode.field("youtube", decode.string)

  decode.success(Playlist(deezer:, spotify:, apple:, youtube:))
}

fn frequency_decoder() -> Decoder(Frequency) {
  use frequency <- decode.field("frequency", station_decoder())
  use name <- decode.field("name", decode.string)
  use verbatims <- decode.field("verbatims", decode.list(decode.string))
  use tags <- decode.field("tags", decode.list(decode.string))
  use artists <- decode.field("artists", decode.list(decode.string))
  use playlist <- decode.field("playlist", playlist_decoder())
  use image <- decode.field("image", decode.string)

  decode.success(Frequency(
    frequency:,
    name:,
    verbatims:,
    tags:,
    artists:,
    playlist:,
    image:,
  ))
}

// UPDATE  ------------------------------------------------

type Msg {
  StartQuizz
  NextQuestion(choice: Option(Choice))
  PreviousQuestion
  ChangeField(String)
  RefreshNudges
  GotResults(Result(Frequency, rsvp.Error))
  StartOver
  ShareFrequency
  NoOp
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    StartOver -> init(Nil)
    StartQuizz -> {
      let assert [#(question, choices), ..rest] = model.next_questions
      #(
        Model(
          ..model,
          current_page: Prompt(question:, choices:),
          next_questions: rest,
          previous_questions: [],
        ),
        effect.none(),
      )
    }
    NextQuestion(None) -> {
      #(model, effect.none())
    }
    NextQuestion(Some(previous_choice)) ->
      case model.current_page, model.next_questions {
        Prompt(question:, choices:), [#(next_question, next_choices), ..rest] -> #(
          Model(
            ..model,
            answers: [previous_choice, ..model.answers],
            next_questions: rest,
            previous_questions: [
              #(question, choices),
              ..model.previous_questions
            ],
            field_content: None,
            current_page: Prompt(
              question: next_question,
              choices: list.shuffle(next_choices),
            ),
          ),
          effect.none(),
        )
        _, [] -> #(
          Model(
            ..model,
            answers: [previous_choice, ..model.answers],
            current_page: LoadingResult,
          ),
          fetch_frequency(model.answers, "en", GotResults),
          // Here we'll call the API to fetch the results
        )
        Home, _ | LoadingResult, _ | Result, _ -> #(model, effect.none())
      }
    ShareFrequency -> {
      case model.result {
        Some(Frequency(image:, ..)) -> #(model, share_frequency(image))
        _ -> #(model, effect.none())
      }
    }
    PreviousQuestion -> {
      let assert Prompt(question: current_question, choices: current_choices) =
        model.current_page
      case model.previous_questions, model.answers {
        [#(previous_question, previous_choices), ..rest],
          [previous_answer, ..answers]
        -> #(
          Model(
            ..model,
            current_page: Prompt(
              question: previous_question,
              choices: list.shuffle(previous_choices),
            ),
            previous_questions: rest,
            next_questions: [
              #(current_question, current_choices),
              ..model.next_questions
            ],
            field_content: case previous_answer {
              CustomChoice(_question, text) -> Some(text)
              _ -> None
            },
            answers: answers,
          ),
          effect.none(),
        )
        _, _ -> #(model, effect.none())
        // Either 1st question or out of bounds
      }
    }
    ChangeField(text) -> #(
      Model(..model, field_content: case text {
        "" -> None
        _ -> Some(text)
      }),
      effect.none(),
    )
    GotResults(Ok(result)) -> #(
      Model(..model, current_page: Result, result: Some(result)),
      effect.none(),
    )
    GotResults(Error(error)) -> {
      echo error
      #(model, effect.none())
    }
    // Re-rendering with the same model should yield different nudges
    RefreshNudges -> {
      let assert Prompt(choices:, question:) = model.current_page
      #(
        Model(
          ..model,
          current_page: Prompt(question:, choices: list.shuffle(choices)),
        ),
        effect.none(),
      )
    }
    NoOp -> #(model, effect.none())
  }
}

// VIEW    ------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  let current_question = list.length(model.previous_questions) + 1
  case model {
    Model(current_page: Home, ..) -> view_home()
    Model(current_page: Prompt(question, choices), ..) ->
      view_prompt(
        question,
        choices,
        model.total_questions,
        current_question,
        model.field_content,
      )
    Model(result: None, ..) -> view_loading()
    Model(result: Some(result), ..) -> view_result(result)
  }
}

fn view_hero(
  header: Element(Msg),
  content: List(Element(Msg)),
  footer: Element(Msg),
  background: String,
) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "flex flex-col "
        <> "w-dvw min-w-xs "
        <> "h-fit min-h-svh "
        <> "bg-cover bg-left "
        <> background,
      ),
    ],
    [
      header,
      html.div([attribute.class("@container hero grow")], [
        html.div([attribute.class("hero-content size-full p-0")], content),
      ]),
      footer,
    ],
  )
}

fn view_home() -> Element(Msg) {
  view_hero(
    view_header(),
    [
      html.div(
        [
          attribute.class(
            "flex flex-col place-items-center"
            <> " py-0 gap-2 @4xl:gap-3 "
            <> "text-neutral-content text-center",
          ),
        ],
        [
          html.h1(
            [
              attribute.class(
                "size-fit mb-2 p-4 pt-1 text-6xl "
                <> "@lg:mb-4 @lg:p-8 @lg:pt-3 "
                <> "@4xl:mb-5 @4xl:p-12 @4xl:pt-5 @4xl:text-7xl "
                <> "text-neutral font-normal italic font-obviously tracking-[-.12em] "
                <> "animate__animated animate__fadeInDown",
              ),
              attribute.style("background", "white"),
            ],
            [html.text("scanne ta fréquence")],
          ),
          html.p(
            [
              attribute.class(
                "px-8 py-4 bg-accent text-xl @4xl:w-lg "
                <> "font-normal text-base-content font-darker",
              ),
            ],
            [
              html.strong([], [
                html.text(
                  "Réponds aux questions pour savoir quelle onde vibre en toi. ",
                ),
              ]),
              html.text(
                "À la fin, on t'attribue une fréquence de radio ...et la vibe qui va avec.",
              ),
            ],
          ),
          html.button(
            [
              attribute.class(
                "btn btn-sm size-fit m-4 pb-1 "
                <> "inline-block "
                <> "@lg:btn-md @4xl:btn-lg "
                <> "font-darker "
                <> "text-xl @lg:text-2xl @4xl:text-3xl "
                <> "animate-bounce-slow",
              ),
              attribute.style(
                "animation-delay",
                int.random(5000) + 1000 |> int.to_string <> "ms",
              ),
              event.on_click(StartQuizz),
            ],
            [html.text("Démarrer l'expérience")],
          ),
        ],
      ),
    ],
    view_footer(),
    "bg-(image:--home-background)",
  )
}

fn view_header() -> Element(Msg) {
  html.header(
    [
      attribute.class(
        "flex flex-row place-self-start mobileLandscape:hidden "
        <> "h-24 w-screen "
        <> "bg-repeat-x bg-(image:--dashed-line-top)",
      ),
    ],
    [],
  )
}

fn view_result_header() -> Element(Msg) {
  html.header([attribute.class("flex flex-col place-self-start bg-black")], [
    html.div(
      [
        attribute.class(
          "h-24 w-screen bg-(image:--header-result-gradient) mobileLandscape:hidden",
        ),
      ],
      [],
    ),
    html.div([attribute.class("flex flex-row w-screen")], [
      html.p(
        [
          attribute.class(
            "grow place-content-center "
            <> "pl-4 pb-1 lg:pl-24 "
            <> "font-darker font-medium text-white text-2xl "
            <> "bg-(image:--noise)",
          ),
        ],
        [html.text("Ma fréquence musicale")],
      ),
      html.div(
        [
          attribute.class(
            "px-3 pb-2 place-content-center "
            <> "bg-white text-black text-3xl font-light font-obviously",
          ),
        ],
        [
          html.span([attribute.class("mr-1 italic tracking-[-.12em]")], [
            html.text("station"),
          ]),
          html.span([attribute.class("font-bold")], [html.text("R")]),
        ],
      ),
    ]),
  ])
}

fn view_footer() -> Element(Msg) {
  html.footer(
    [
      attribute.class(
        "relative flex flex-col-reverse gap-0 place-content-end mobileLandscape:hidden",
      ),
    ],
    [
      html.img([
        attribute.class("z-1 h-4 lg:h-6 4xl:h-8 w-full object-cover"),
        attribute.src("./src/assets/dashed-line-bottom.svg"),
      ]),
      html.img([
        attribute.class(
          "landscape:absolute landscape:bottom-6 h-18 lg:h-24 place-self-end",
        ),
        attribute.src("./src/assets/logos.svg"),
      ]),
    ],
  )
}

fn view_prompt(
  question: Question,
  choices: Answers,
  total_questions: Int,
  question_number: Int,
  field_content: Option(String),
) -> Element(Msg) {
  view_hero(
    view_header(),
    [
      html.div(
        [
          attribute.class(
            "flex flex-col w-full "
            <> "py-0 mb-8 mobileLandscape:mb-0 @4xl:mb-32 gap-2 "
            <> "@4xl:gap-7 text-neutral-content text-center",
          ),
        ],
        [
          view_step_indicator(total_questions, question_number),
          html.h1(
            [
              attribute.class(
                "p-2 text-3xl "
                <> "@4xl:text-5xl "
                <> "text-neutral font-normal italic font-obviously tracking-[-.08em] "
                <> "animate__animated animate__fadeIn",
              ),
            ],
            [html.text(question.question)],
          ),
          view_field_nav(
            total_questions,
            question_number,
            question,
            field_content,
          ),
          choices |> list.take(4) |> view_choices,
        ],
      ),
    ],
    view_footer(),
    "bg-(image:--duotone-gradient)",
  )
}

fn view_step_indicator(total_steps: Int, current_step: Int) -> Element(Msg) {
  let steps = list.range(1, total_steps)
  html.ul(
    [
      attribute.class(
        "steps w-full @4xl:w-xl place-self-center "
        <> "text-center text-neutral font-semibold font-darker text-xl",
      ),
    ],
    list.map(steps, fn(step) {
      html.li(
        [
          attribute.class(
            "step"
            <> case step <= current_step {
              True -> " step-primary"
              False -> ""
            },
          ),
        ],
        [
          html.span([attribute.class("pb-1 step-icon place-content-center")], [
            step |> int.to_string |> html.text,
          ]),
        ],
      )
    }),
  )
}

fn view_choices(choices: List(Choice)) -> Element(Msg) {
  let refresh_button =
    html.button(
      [
        attribute.class("btn btn-primary btn-circle btn-xs opacity-70"),
        event.on_click(RefreshNudges),
      ],
      [html.span([attribute.class("fa-solid fa-rotate-right")], [])],
    )
  let choice_buttons = list.map(choices, view_choice_button)
  html.div(
    [
      attribute.class(
        "flex flex-col place-items-center gap-2 px-6 my-6 @lg:landscape:my-1",
      ),
    ],
    [
      html.p([attribute.class("font-darker pb-1 @lg:text-xl")], [
        html.text("Je choisis parmi ces propositions :"),
      ]),
      html.div(
        [
          attribute.class(
            "flex flex-wrap place-content-center " <> "gap-2 font-darker",
          ),
        ],
        list.reverse([refresh_button, ..choice_buttons]),
      ),
    ],
  )
}

fn view_choice_button(choice: Choice) -> Element(Msg) {
  let assert PromptChoice(answer, _) = choice
  html.button(
    [
      attribute.class(
        "btn btn-soft btn-xs "
        <> "inline-block "
        <> "px-5 pb-1 "
        <> "opacity-50 shadow-none "
        <> "transition "
        <> "text-sm @lg:text-lg "
        <> "hover:opacity-90 hover:shadow-(color:--color-primary) "
        <> "active:shadow-md active:shadow-(color:--color-primary) active:opacity-100 "
        <> "animate-bounce-slow",
      ),
      attribute.style(
        "animation-delay",
        int.random(2000) + 3000 |> int.to_string <> "ms",
      ),
      event.on_click(ChangeField(answer)),
    ],
    [html.text(answer)],
  )
}

fn view_field_nav(
  total_steps: Int,
  current_step: Int,
  current_question: Question,
  field_content: Option(String),
) -> Element(Msg) {
  let input_min_length = 3
  let input_max_length = 50
  let field_validation_string =
    "(?=[\\p{L}\\p{M}\\p{P}\\s\\d]*).{"
    <> int.to_string(input_min_length)
    <> ","
    <> int.to_string(input_max_length)
    <> "}"
  let assert Ok(field_validation_regex) =
    regexp.from_string(field_validation_string)
  let field_disabled =
    option.is_none(field_content)
    || !regexp.check(field_validation_regex, option.unwrap(field_content, ""))
  html.div(
    [attribute.class("flex flex-row w-full place-items-center gap-2 px-4")],
    [
      html.button(
        [
          attribute.class("btn btn-circle btn-sm @lg:btn-md @4xl:btn-lg"),
          attribute.hidden(current_step == 1),
          event.on_click(PreviousQuestion),
        ],
        [html.text("←")],
      ),
      html.label(
        [
          attribute.class(
            "grow input validator input-md rounded-full @lg:input-lg @4xl:input-xl "
            <> "font-darker "
            <> "text-xl @lg:text-2xl @4xl:text-3xl "
            <> "text-base-content font-medium",
          ),
        ],
        [
          html.input([
            attribute.class("pb-1 pl-3"),
            attribute.type_("text"),
            attribute.pattern(field_validation_string),
            attribute.required(True),
            attribute.placeholder("J’écris ma propre réponse …"),
            attribute.attribute("minlength", int.to_string(input_min_length)),
            attribute.attribute("maxlength", int.to_string(input_max_length)),
            event.on_input(ChangeField),
            event.on_keypress(fn(key) {
              case key, field_disabled {
                "Enter", False ->
                  NextQuestion(
                    field_content
                    |> option.map(CustomChoice(current_question, _)),
                  )
                _, _ -> NoOp
              }
            }),
            attribute.value(field_content |> option.unwrap("")),
          ]),
          html.button(
            [
              attribute.class(
                "btn btn-circle btn-primary btn-xs @lg:btn-sm @4xl:btn-md @lg:text-md @4xl:text-lg font-sans",
              ),
              attribute.disabled(field_disabled),
              event.on_click(NextQuestion(
                field_content |> option.map(CustomChoice(current_question, _)),
              )),
            ],
            [
              html.text(case current_step == total_steps {
                True -> "✓"
                False -> "→"
              }),
            ],
          ),
        ],
      ),
    ],
  )
}

fn view_loading() -> Element(Msg) {
  html.div([attribute.class("hero min-h-svh")], [
    html.div(
      [
        attribute.class(
          "w-svw h-svh min-w-svw min-h-svh animate-scroll-down bg-(image:--loading-gradient)",
        ),
        attribute.style(
          "animation-delay",
          "-" <> int.random(60) |> int.to_string <> "s",
        ),
        attribute.style("background-size", "100% 200%"),
      ],
      [
        html.div(
          [
            attribute.class(
              "h-svh min-h-svh w-full "
              <> "bg-(image:--noise) mix-blend-screen opacity-70",
            ),
          ],
          [],
        ),
      ],
    ),
    html.div([attribute.class("hero-overlay animate-pulse-darken")], []),
    html.div([attribute.class("hero-content text-center")], [
      html.h1(
        [
          attribute.class(
            "text-5xl text-neutral-content font-light italic font-obviously tracking-[-.08em]",
          ),
        ],
        [html.text("calcul de ta fréquence ...")],
      ),
    ]),
  ])
}

fn view_result(result: Frequency) -> Element(Msg) {
  let background = case result.frequency {
    Slower | Slow -> "bg-(image:--house-result-gradient)"
    Faster | Fast -> "bg-(image:--techno-result-gradient)"
  }
  let pill_color = case result.frequency {
    // Make tailwind preprocessor happy : bg-primary bg-secondary
    Faster | Fast -> "primary"
    Slower | Slow -> "secondary"
  }
  let genre = case result.frequency {
    Slower | Slow -> "House solaire"
    Faster | Fast -> "Techno sombre"
  }
  let location = case result.frequency {
    Slower | Slow -> "L'Atrium"
    Faster | Fast -> "Le Refuge"
  }
  let Playlist(
    deezer: deezer_link,
    spotify: spotify_link,
    apple: apple_music_link,
    youtube: youtube_link,
  ) = result.playlist
  let frequency_pane =
    html.section(
      [
        attribute.class(
          "flex flex-col p-4 landscape:lg:p-24 landscape:lg:pt-8 place-self-stretch "
          <> "shadow-lg/30 "
          <> background
          <> " text-2xl mobileLandscape:text-lg font-darker font-extrabold",
        ),
      ],
      [
        html.h1(
          [
            attribute.class(
              "pb-1 mb-2 "
              <> "text-neutral-content text-6xl mobileLandscape:text-4xl "
              <> "font-obviously font-normal italic tracking-[-.06em] "
              <> "animate__animated animate__fadeInUp",
            ),
            attribute.style("animation-delay", "400ms"),
          ],
          [result.frequency |> station_to_string |> html.text],
        ),
        html.p([attribute.class("font-medium")], [
          html.text(genre <> " dans "),
          html.span(
            [
              attribute.class(
                "pb-1 px-3 bg-"
                <> pill_color
                <> " font-bold text-md mobileLandscape:text-sm rounded-3xl",
              ),
            ],
            [html.text(location)],
          ),
        ]),
        html.p([], [html.text("Le 31 juillet à la Rotonde Stalingrad")]),
        html.h2(
          [
            attribute.class(
              "grow min-h-[40vh] mobileLandscape:min-h-[20vh] place-content-center "
              <> "text-neutral-content text-6xl mobileLandscape:text-4xl "
              <> "font-obviously font-normal italic tracking-[-.06em] "
              <> "animate__animated animate__fadeInUp",
            ),
          ],
          [html.text(result.name)],
        ),
        html.div(
          [attribute.class("flex flex-wrap gap-2")],
          {
            use pills, color <- list.map2(
              [result.tags, result.verbatims, result.artists],
              ["bg-neutral-content", "bg-accent", "bg-" <> pill_color],
            )
            use pill <- list.map(pills)
            html.p(
              [
                attribute.class(
                  "pb-1 px-3 "
                  <> color
                  <> " shadow-lg font-bold text-md mobileLandscape:text-sm rounded-3xl "
                  <> "animate-bounce-slow",
                ),
                attribute.style(
                  "animation-delay",
                  int.random(7000) + 3000 |> int.to_string <> "ms",
                ),
              ],
              [html.text(pill)],
            )
          }
            |> list.flatten
            |> list.shuffle,
        ),
      ],
    )
  let cta_pane =
    html.section(
      [
        attribute.class(
          "shrink py-4 mobileLandscape:py-2 px-8 "
          <> "flex flex-col text-center place-items-center place-content-center gap-4 "
          <> "text-2xl mobileLandscape:text-lg/6 font-darker font-extrabold",
        ),
      ],
      [
        html.p([], [
          html.text(
            "Ce résultat a été conçu entièrement en fonction de tes choix !",
          ),
        ]),
        html.p([attribute.class("font-semibold")], [
          html.text(
            "Nous avons associé tes réponses à des propositions similaires...",
          ),
        ]),
        html.p([], [
          html.text(
            "Viens découvrir l’ambiance qui te correspond  le 31 juillet à la Rotonde avec Éclectique et OD.",
          ),
        ]),
        html.div(
          [
            attribute.class(
              "flex flex-col text-center place-items-center gap-2",
            ),
          ],
          [
            html.a(
              [
                attribute.class(
                  "pb-1 mb-1 btn btn-"
                  <> pill_color
                  <> " btn-sm mobileLandscape:btn-xs text-xl mobileLandscape:text-lg shadow-lg "
                  <> "animate-bounce-slow",
                ),
                attribute.style("animation-delay", "1s"),
                attribute.href(
                  "https://shotgun.live/fr/events/station-r-eclectique-x-od",
                ),
                attribute.target("_blank"),
                attribute.rel("noopener noreferrer"),
              ],
              [html.text("Prends ta place")],
            ),
            html.button(
              [
                attribute.class(
                  "pb-1 btn btn-sm mobileLandscape:btn-xs text-xl mobileLandscape:text-lg shadow-lg",
                ),
                event.on_click(ShareFrequency),
              ],
              [html.text("Partage ta fréquence")],
            ),
            html.p([], [html.text("Écoute la playlist associée :")]),
            html.div([attribute.class("flex gap-2")], [
              html.a(
                [
                  attribute.class(
                    "place-content-center btn btn-ghost btn-circle btn-sm text-xl",
                  ),
                  attribute.href(deezer_link),
                  attribute.target("_blank"),
                  attribute.rel("noopener noreferrer"),
                ],
                [html.span([attribute.class("fa-brands fa-deezer ")], [])],
              ),
              html.a(
                [
                  attribute.class(
                    "place-content-center btn btn-ghost btn-circle btn-sm text-xl",
                  ),
                  attribute.href(spotify_link),
                  attribute.target("_blank"),
                  attribute.rel("noopener noreferrer"),
                ],
                [html.span([attribute.class("fa-brands fa-spotify")], [])],
              ),
              html.a(
                [
                  attribute.class(
                    "place-content-center btn btn-ghost btn-circle btn-sm text-xl",
                  ),
                  attribute.href(apple_music_link),
                  attribute.target("_blank"),
                  attribute.rel("noopener noreferrer"),
                ],
                [html.span([attribute.class("fa-brands fa-apple")], [])],
              ),
              html.a(
                [
                  attribute.class(
                    "place-content-center btn btn-ghost btn-circle btn-sm text-xl",
                  ),
                  attribute.href(youtube_link),
                  attribute.target("_blank"),
                  attribute.rel("noopener noreferrer"),
                ],
                [html.span([attribute.class("fa-brands fa-youtube")], [])],
              ),
            ]),
          ],
        ),
      ],
    )
  html.div(
    [
      attribute.class(
        "flex flex-col " <> "w-dvw min-w-xs " <> "h-full min-h-svh",
      ),
    ],
    [
      view_result_header(),
      html.div(
        [
          attribute.class(
            "grow flex flex-col landscape:flex-row gap-0 text-neutral",
          ),
        ],
        [frequency_pane, cta_pane],
      ),
      view_footer(),
    ],
  )
}

// DATA    ------------------------------------------------

fn load_questionnaire() -> Questionnaire {
  let questions: List(#(Question, Answers)) = [
    #(
      Question(
        question_id: "place",
        question: "Un lieu idéal pour écouter de la musique ?",
      ),
      [
        PromptChoice(answer: "En plein air", station: Slower),
        PromptChoice(answer: "Devant un coucher de soleil", station: Slower),
        PromptChoice(answer: "Un club cosy", station: Slow),
        PromptChoice(answer: "Un rooftop avec vue", station: Slow),
        PromptChoice(answer: "Un club sombre avec strobos", station: Fast),
        PromptChoice(
          answer: "Dans une cave où le temps disparait",
          station: Fast,
        ),
        PromptChoice(answer: "Une friche industrielle", station: Faster),
        PromptChoice(answer: "Devant un systeme son massif", station: Faster),
      ],
    ),
    #(
      Question(
        question_id: "spirit",
        question: "Quel est ton tempo intérieur ce soir ?",
      ),
      [
        PromptChoice(answer: "Rire en dansant", station: Slower),
        PromptChoice(answer: "Bouger à ma façon", station: Slower),
        PromptChoice(answer: "Planer en solo", station: Slow),
        PromptChoice(answer: "Me laisser porter par la mélodie", station: Slow),
        PromptChoice(answer: "Me perdre dans le rythme", station: Fast),
        PromptChoice(answer: "Être en phase avec la foule", station: Fast),
        PromptChoice(answer: "Une transe perpétuelle", station: Faster),
        PromptChoice(answer: "Besoin que ca galope", station: Faster),
      ],
    ),
    #(Question(question_id: "outfit", question: "Ta tenue parfaite ?"), [
      PromptChoice(answer: "Fluide et colorée", station: Slower),
      PromptChoice(answer: "Vintage et disco", station: Slower),
      PromptChoice(answer: "Décontractée et stylée", station: Slow),
      PromptChoice(answer: "Pleine de paillettes", station: Slow),
      PromptChoice(answer: "Sobre et efficace", station: Fast),
      PromptChoice(answer: "Noir c'est noir", station: Fast),
      PromptChoice(answer: "Tout terrain", station: Faster),
      PromptChoice(answer: "Pratique et sport", station: Faster),
    ]),
    #(
      Question(
        question_id: "aesthetic",
        question: "Si tu devais choisir un détail dans la musique…",
      ),
      [
        PromptChoice(answer: "Une basse funky", station: Slower),
        PromptChoice(answer: "Des vocaux puissants", station: Slower),
        PromptChoice(answer: "Une mélodie entêtante", station: Slower),
        PromptChoice(answer: "Une nappe aérienne", station: Slow),
        PromptChoice(answer: "Un synthé acide", station: Slow),
        PromptChoice(answer: "Des percussions organiques", station: Slow),
        PromptChoice(answer: "Un ostinato hypnotique", station: Fast),
        PromptChoice(answer: "Un rythme envoutant", station: Fast),
        PromptChoice(answer: "Des basses progressives", station: Fast),
        PromptChoice(answer: "Un kick sec et rapide", station: Faster),
        PromptChoice(answer: "Un rythme extatique", station: Faster),
        PromptChoice(answer: "Une rolling bassline", station: Faster),
      ],
    ),
    #(
      Question(
        question_id: "fuel",
        question: "Quel est ton carburant en soirée ?",
      ),
      [
        PromptChoice(answer: "Un cocktail fruité", station: Slower),
        PromptChoice(answer: "Une infusion fraîche", station: Slower),
        PromptChoice(answer: "Une bière fraîche", station: Slower),
        PromptChoice(answer: "Un kombutcha", station: Slow),
        PromptChoice(answer: "Un bissap", station: Slow),
        PromptChoice(answer: "Une boisson énergisante", station: Slow),
        PromptChoice(answer: "De l'alcool fort", station: Fast),
        PromptChoice(answer: "Un soda bien pétillant", station: Fast),
        PromptChoice(answer: "Une tournée de B52", station: Fast),
        PromptChoice(answer: "De l'eau pour rester hydraté", station: Faster),
        PromptChoice(answer: "Rien", station: Faster),
        PromptChoice(answer: "Juste la musique", station: Faster),
      ],
    ),
  ]
  Questionnaire(questions:)
}

fn station_to_string(station: Station) -> String {
  case station {
    Faster -> "108.9 FM"
    Fast -> "105.6 FM"
    Slow -> "101.1 FM"
    Slower -> "97.3 FM"
  }
}

// FFI     ------------------------------------------------

@external(javascript, "./share.ffi.mjs", "share_image")
fn share_image(_image_data: String) -> Result(Nil, String) {
  Ok(Nil)
}

fn share_frequency(image_data: String) -> Effect(Msg) {
  use _ <- effect.from
  case share_image(image_data) {
    Ok(_) -> Nil
    Error(message) -> {
      echo message
      Nil
    }
  }
}
