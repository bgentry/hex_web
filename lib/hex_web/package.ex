defmodule HexWeb.Package do
  use Ecto.Model

  import Ecto.Query, only: [from: 2]
  import HexWeb.Validation
  require Ecto.Validator
  alias HexWeb.Util

  queryable "packages" do
    field :name, :string
    belongs_to :owner, HexWeb.User
    field :meta, :string
    has_many :releases, HexWeb.Release
    field :created_at, :datetime
    field :updated_at, :datetime
  end

  validatep validate_create(package),
    also: validate(),
    also: unique([:name], case_sensitive: false, on: HexWeb.Repo)

  validatep validate(package),
    name: present() and type(:string) and has_format(~r"^[a-z]\w*$"),
    meta: validate_meta()

  defp validate_meta(field, arg) do
    errors =
      Ecto.Validator.bin_dict(arg,
        contributors: type({ :array, :string }),
        licenses:     type({ :array, :string }),
        links:        type({ :dict, :string, :string }),
        description:  type(:string))
    if errors == [], do: [], else: [{ field, errors }]
  end

  @meta_fields ["contributors", "description", "links", "licenses"]

  def create(name, owner, meta) do
    now = Util.ecto_now
    meta = Dict.take(meta, @meta_fields)
    package = owner.packages.new(name: name, meta: meta, created_at: now,
                                 updated_at: now)

    case validate_create(package) do
      [] ->
        package = package.meta(JSON.encode!(meta))
        { :ok, HexWeb.Repo.create(package).meta(meta).releases([]) }
      errors ->
        { :error, errors }
    end
  end

  def update(package, meta) do
    meta = Dict.take(meta, @meta_fields)

    case validate(package.meta(meta)) do
      [] ->
        package = package.updated_at(Util.ecto_now)
        HexWeb.Repo.update(package.meta(JSON.encode!(meta)))
        { :ok, package.meta(meta) }
      errors ->
        { :error, errors }
    end
  end

  def get(name) do
    package =
      from(p in HexWeb.Package,
           where: p.name == ^name,
           preload: [:releases],
           limit: 1)
      |> HexWeb.Repo.all
      |> List.first

    if package do
      package.update_meta(&JSON.decode!(&1))
             .releases(HexWeb.Release.all(package))
    end
  end

  def all(page, count, search \\ nil) do
    # TODO: Sort releases by Version.compare/2

    from(p in HexWeb.Package,
         preload: [:releases],
         order_by: p.name)
    |> Util.paginate(page, count)
    |> Util.searchinate(:name, search)
    |> HexWeb.Repo.all
  end

  def count do
    HexWeb.Repo.all(from(p in HexWeb.Package, select: count(p.id)))
    |> List.first
  end
end

defimpl HexWeb.Render, for: HexWeb.Package.Entity do
  import HexWeb.Util

  def render(package) do
    releases =
      Enum.map(package.releases, fn release ->
        release.__entity__(:keywords)
        |> Dict.take([:version, :git_url, :git_ref, :created_at, :updated_at])
        |> Dict.update!(:created_at, &to_iso8601/1)
        |> Dict.update!(:updated_at, &to_iso8601/1)
        |> Dict.put(:url, api_url(["packages", package.name, "releases", release.version]))
      end)

    package.__entity__(:keywords)
    |> Dict.take([:name, :meta, :created_at, :updated_at])
    |> Dict.update!(:created_at, &to_iso8601/1)
    |> Dict.update!(:updated_at, &to_iso8601/1)
    |> Dict.put(:url, api_url(["packages", package.name]))
    |> Dict.put(:releases, releases)
  end
end
